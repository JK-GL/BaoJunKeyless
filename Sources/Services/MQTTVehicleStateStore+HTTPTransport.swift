import Foundation

extension MQTTVehicleStateStore {
    /// 官方车况策略：queryDefaultCarStatus 为完整权威快照，车辆下发 conditionPollTime（实车为 3 秒）。
    static let backgroundActiveHTTPPollInterval: TimeInterval = 3
    static let backgroundIdleHTTPPollInterval: TimeInterval = 25
    static let backgroundSyncOffHTTPPollInterval: TimeInterval = 60
    static let tirePressureRefreshInterval: TimeInterval = 60

    /// 前台始终按官方车况周期；后台仅在近车/未锁/门窗打开等活跃期保持快刷。
    func currentHTTPPollInterval(now: Date = Date()) -> TimeInterval {
        let officialInterval = min(max(vehicleHTTPPollInterval, 2), 10)
        if isAppInForeground { return officialInterval }

        let bodyOpen = dashboard.doorStatusText.hasPrefix("未关")
            || dashboard.windowStatusText.hasPrefix("未关")
            || dashboard.tailgateStatusText.hasPrefix("已开")
        let vehicleActive = hasCompletedBLEAuth
            || state.hasLiveBLEProximity
            || state.phoneNearby
            || state.locked == false
            || bodyOpen
            || localDoorLockHoldUntil.map { now < $0 } == true

        if keylessSettingsStore.settings.backgroundStateSyncEnabled {
            return vehicleActive ? max(officialInterval, Self.backgroundActiveHTTPPollInterval) : Self.backgroundIdleHTTPPollInterval
        }
        return vehicleActive ? Self.backgroundIdleHTTPPollInterval : Self.backgroundSyncOffHTTPPollInterval
    }

    /// 前后台 / 设置切换时重算 HTTP 轮询与 MQTT 保活策略
    func applyBackgroundRuntimeSettings(reason: String) {
        let settings = keylessSettingsStore.settings
        let interval = currentHTTPPollInterval()
        let modeText: String
        if isAppInForeground {
            modeText = "前台 · \(Int(interval))s"
        } else if settings.backgroundStateSyncEnabled {
            modeText = "后台同步开 · \(Int(interval))s"
        } else {
            modeText = "后台同步关 · \(Int(interval))s"
        }

        // 运行策略只进控制台事件日志，不进错误日志
        // 用户可见：与轮询/扫描一样可 ×N 合并
        vehicleEventLogStore.addCoalesced(
            .system,
            "后台状态同步",
            detail: "\(modeText) · \(backgroundReasonText(reason))",
            identity: "bg-state-sync|\(isAppInForeground ? "fg" : "bg")|\(settings.backgroundStateSyncEnabled ? 1 : 0)|\(Int(interval))",
            mergeWindow: 180
        )

        // 始终用当前策略重挂 HTTP 定时器：前台按官方 conditionPollTime，后台按活跃度降频。
        if credentialsStore.accessToken.isEmpty {
            httpTimer?.invalidate()
            httpTimer = nil
            return
        }
        startHTTPPolling(immediate: false)

        // 后台且允许状态同步时，尽量保持 MQTT
        if !isAppInForeground
            && settings.backgroundStateSyncEnabled
            && settings.mqttEnabled {
            if mqttStatus != .connected && mqttStatus != .connecting {
                vehicleEventLogStore.addCoalesced(
                    .system,
                    "后台 MQTT 重连",
                    detail: "状态同步开启 · 尝试保持车况",
                    identity: "bg-mqtt-reconnect",
                    mergeWindow: 120
                )
                reconnect()
            }
        }
    }

    private func backgroundReasonText(_ reason: String) -> String {
        switch reason {
        case "enter-background": return "进入后台"
        case "enter-foreground": return "回到前台"
        case "settings-init": return "启动"
        case "settings-change": return "设置变更"
        case "geofence-enter": return "进入围栏"
        default: return reason
        }
    }

    func startHTTPPolling(immediate: Bool) {
        httpTimer?.invalidate()
        // 官方同款：前台完整车况约 3s；MQTT 不再让 HTTP 降频，后台按车辆活跃度自动降频。
        let interval = currentHTTPPollInterval()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 后台关闭状态同步时仍允许极低频兜底，但不做 immediate 狂刷
            self.pollHTTPOnce(userInitiated: false, completion: nil)
            // 根据前后台与车辆活跃度自适应下一次间隔
            let next = self.currentHTTPPollInterval()
            if abs((self.httpTimer?.timeInterval ?? 0) - next) > 0.5 {
                self.startHTTPPolling(immediate: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        httpTimer = timer
        if immediate {
            pollHTTPOnce(userInitiated: false, completion: nil)
        }
    }

    /// MQTT/BLE 事件只唤醒 HTTP 权威刷新；短时间连续半包合并为一次请求。
    func scheduleHTTPRefreshFromRealtime(reason: String) {
        _ = reason
        guard !credentialsStore.accessToken.isEmpty else { return }
        httpRefreshWakeWorkItem?.cancel()
        let now = Date()
        let elapsed = lastHTTPWakeRefreshAt.map { now.timeIntervalSince($0) } ?? 10
        let delay = max(0.12, 0.8 - elapsed)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastHTTPWakeRefreshAt = Date()
            if self.isHTTPPollInFlight {
                // 事件发生在请求期间，完成后必须补刷一次，避免拿到事件前快照。
                self.pendingHTTPPollAfterCurrent = true
                return
            }
            self.pollHTTPOnce(userInitiated: false, completion: nil)
        }
        httpRefreshWakeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 胎压独立低频刷新，不阻塞三秒车况主请求。
    func refreshTirePressureIfNeeded(carInfo: [String: String], force: Bool) {
        let now = Date()
        if !force, let last = lastTirePressureUpdate,
           now.timeIntervalSince(last) < Self.tirePressureRefreshInterval { return }
        let vin = carInfo["vin"] ?? credentialsStore.vin
        guard !vin.isEmpty, !credentialsStore.accessToken.isEmpty else { return }
        lastTirePressureUpdate = now
        SGMWApiClient.shared.queryTirePressureResult(
            accessToken: credentialsStore.accessToken,
            vin: vin
        ) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard case .success(let tirePressure) = result, !tirePressure.isEmpty else { return }
                let updated = VehicleStatusMapper.tirePressureDashboard(from: tirePressure, base: self.dashboard)
                self.applyDashboard(updated)
            }
        }
    }

    private func finishHTTPPoll(ok: Bool, message: String) {
        isHTTPPollInFlight = false
        let callbacks = pendingHTTPPollCompletions
        pendingHTTPPollCompletions.removeAll()
        callbacks.forEach { $0(ok, message) }

        guard pendingHTTPPollAfterCurrent else { return }
        pendingHTTPPollAfterCurrent = false
        DispatchQueue.main.async { [weak self] in
            self?.pollHTTPOnce(userInitiated: false, completion: nil)
        }
    }

    /// 刷新车况。userInitiated 时写事件日志并回调结果文案。
    func pollHTTPOnce(userInitiated: Bool = false, completion: ((Bool, String) -> Void)? = nil) {
        let store = credentialsStore
        let token = store.accessToken
        guard !token.isEmpty else {
            let message = "车况刷新失败：Token 为空"
            if userInitiated {
                vehicleEventLogStore.add(.error, "车况刷新失败", detail: message)
            }
            completion?(false, message)
            return
        }

        if let completion { pendingHTTPPollCompletions.append(completion) }
        if isHTTPPollInFlight {
            // 当前请求本身就是完整权威快照；复用其结果，不再排队重复请求。
            return
        }
        isHTTPPollInFlight = true

        if userInitiated {
            vehicleEventLogStore.add(.action, "车况刷新开始", detail: "正在请求 queryDefaultCarStatus")
        }

        VehicleHTTPRefreshRequester.shared.fetch(accessToken: token, includeTirePressure: false) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let refreshResult):
                    self.lastHTTPUpdate = refreshResult.fetchedAt
                    let httpCollect = parseTimestamp(refreshResult.carStatus["collectTime"]) ?? refreshResult.fetchedAt

                    // 车辆配置下发官方轮询秒数；异常值仍限制在 2...10 秒。
                    if let configured = parseDouble(refreshResult.carInfo["conditionPollTime"]), configured > 0 {
                        let nextInterval = min(max(configured, 2), 10)
                        if abs(self.vehicleHTTPPollInterval - nextInterval) > 0.1 {
                            self.vehicleHTTPPollInterval = nextInterval
                        }
                    }

                    self.applyHTTPMeta(carInfo: refreshResult.carInfo, carStatus: refreshResult.carStatus)
                    self.refreshTirePressureIfNeeded(carInfo: refreshResult.carInfo, force: userInitiated)

                    var newState = self.mapHTTPToVehicleState(refreshResult.carStatus)
                    var newDashboard = self.mapHTTPToDashboard(refreshResult.carStatus)
                    if !refreshResult.tirePressure.isEmpty {
                        newDashboard = VehicleStatusMapper.tirePressureDashboard(
                            from: refreshResult.tirePressure,
                            base: newDashboard
                        )
                    }
                    newState.online = true
                    newDashboard = Self.stripDashboardBodyCacheSuffix(newDashboard)

                    let mergeMode: VehicleHTTPMergeMode = userInitiated ? .full : .pollFull
                    let mergeNote = self.mergeHTTPBaseState(
                        newState: newState,
                        dashboard: newDashboard,
                        mode: mergeMode,
                        httpCollectAt: httpCollect,
                        sourceFields: refreshResult.carStatus
                    )
                    if mergeNote != "丢弃旧HTTP" {
                        self.lastHTTPBodyCollectAt = httpCollect
                        self.rememberHTTPDoorWindowAuthority(from: refreshResult.carStatus, at: httpCollect)
                    }
                    // 成功轮询只进控制台事件日志，不写错误日志

                    let fingerprint = self.httpPollStatusFingerprint()
                    let body = bodyFieldsSummary(refreshResult.carStatus)
                    let message = "车况已更新 · HTTP(\(mergeMode.rawValue)\(mergeNote.isEmpty ? "" : "·\(mergeNote)")) · \(formatTime(refreshResult.fetchedAt)) · 锁=\(self.dashboard.lockStatusText) 门=\(self.dashboard.doorStatusText) 窗=\(self.dashboard.windowStatusText) 尾=\(self.dashboard.tailgateStatusText) · 主驾=\(self.dashboard.driverDoorStatusText)/副驾=\(self.dashboard.passengerDoorStatusText)/左后=\(self.dashboard.leftRearDoorStatusText)/右后=\(self.dashboard.rightRearDoorStatusText) · 电=\(self.dashboard.batteryPercentValue.map(String.init) ?? "--")% 空调=\(self.dashboard.acTemperatureText)\(body.isEmpty ? "" : " · raw:\(body)")"

                    if userInitiated {
                        self.lastHTTPPollLogFingerprint = fingerprint
                        self.vehicleEventLogStore.add(.action, "车况刷新成功", detail: message)
                    } else if mergeNote == "丢弃旧HTTP" {
                        // 旧包丢弃：静默，不刷日志
                    } else if self.lastHTTPPollLogFingerprint == fingerprint {
                        // 状态没变：不写新日志，只把同类心跳合并成 ×N（很久才露一次）
                        self.vehicleEventLogStore.addCoalesced(
                            .action,
                            "车况轮询无变化",
                            detail: "锁=\(self.dashboard.lockStatusText) 门=\(self.dashboard.doorStatusText) 窗=\(self.dashboard.windowStatusText) 尾=\(self.dashboard.tailgateStatusText)",
                            identity: "http-poll-unchanged",
                            mergeWindow: 600
                        )
                    } else {
                        // 有变化：记一条；同指纹短时间重复会 ×N
                        self.lastHTTPPollLogFingerprint = fingerprint
                        self.vehicleEventLogStore.addCoalesced(
                            .action,
                            "车况轮询更新",
                            detail: message,
                            identity: "http-poll-changed|\(fingerprint)",
                            mergeWindow: 120
                        )
                    }
                    self.finishHTTPPoll(ok: true, message: message)

                case .failure(let error):
                    let message = "车况刷新失败：\(error.localizedDescription)"
                    CrashLogger.shared.mark("HTTP", "status refresh failed: \(error.localizedDescription)")
                    // 网络失败时明确离线，避免旧门窗/车锁继续被当成“实时真实状态”
                    self.markVehicleStatusOffline(reason: error.localizedDescription, userInitiated: userInitiated)
                    if userInitiated {
                        self.vehicleEventLogStore.add(.error, "车况刷新失败", detail: message)
                    }
                    self.finishHTTPPoll(ok: false, message: message)
                }
            }
        }
    }

    func mapHTTPToVehicleState(_ s: [String: String]) -> VehicleState {
        VehicleStatusMapper.httpState(from: s, base: state)
    }

    func mapHTTPToDashboard(_ s: [String: String]) -> VehicleDashboardState {
        VehicleStatusMapper.httpDashboard(from: s, base: dashboard)
    }

    /// 记住 HTTP 全量门窗明细，供 MQTT 半包假开门过滤
    func rememberHTTPDoorWindowAuthority(from carStatus: [String: String], at: Date) {
        var snap: [String: String] = [:]
        for key in Self.doorWindowOpenFieldKeys {
            if let value = carStatus[key], !value.isEmpty {
                snap[key] = value
            }
        }
        // 至少有一个门窗字段才记；否则保留旧权威
        guard !snap.isEmpty else { return }
        lastHTTPDoorWindowAuthority = (fields: snap, at: at)
        // HTTP 是权威基线：开与关都同步，确保后续 MQTT 反向变化能被识别并触发 HTTP。
        for key in Set(Self.doorWindowOpenFieldKeys + Self.bodyFieldKeys) {
            if let trusted = carStatus[key], !trusted.isEmpty {
                lastMqttFields[key] = trusted
            }
        }
    }

    /// 车况拉失败时：标记离线；若状态已过期，清掉门窗等“开闭态”避免 UI/无感继续当真。
    /// 车锁 `locked` 若刚被 BLE 本地回写（timestamp 很新）则保留。
    func markVehicleStatusOffline(reason: String, userInitiated: Bool) {
        let now = Date()
        // MQTT 只负责提示/唤醒，不再作为车辆状态真值；HTTP 失败必须如实标记离线。
        var next = state
        let previousOnline = next.online
        next.online = false

        let age = now.timeIntervalSince(next.timestamp)
        let stale = age > 90
        if stale {
            // 过期门窗/尾门不再当真；否则离线时会一直显示“门开着/窗开着”
            next.doorsClosed = nil
            next.driverDoorOpen = nil
            next.trunkOpen = nil
            next.windowsClosed = nil
            // gear/power/key 也别继续用过期硬门禁
            if next.gear != .unknown { next.gear = .unknown }
            if next.power != .unknown { next.power = .unknown }
            // 离线陈旧 keyStatus=2 常把数字钥匙误显示成“物理钥匙车内”
            if next.physicalKeyPosition != .unknown {
                next.physicalKeyPosition = .unknown
            }
            // locked：仅当本地很久没更新才清空；BLE 刚回写的锁态 timestamp 新，会保留
            if age > 180 {
                next.locked = nil
            }
        }

        if previousOnline != next.online || stale {
            apply(next)
        }

        if stale {
            var dash = dashboard
            dash = Self.markDashboardBodyStatusStale(dash)
            applyDashboard(dash)
            vehicleEventLogStore.addThrottled(
                .warning,
                "车况已离线缓存",
                detail: "网络不可用，门窗/尾门等开闭态已停止当真 · \(reason)",
                identity: "status-offline-stale",
                minimumInterval: 20
            )
        } else if previousOnline && userInitiated {
            vehicleEventLogStore.addThrottled(
                .warning,
                "车况暂时离线",
                detail: "网络不可用，暂时使用最近状态 · \(reason)",
                identity: "status-offline-temp",
                minimumInterval: 20
            )
        }
    }

    static func markDashboardBodyStatusStale(_ dashboard: VehicleDashboardState) -> VehicleDashboardState {
        var dash = dashboard
        func cache(_ text: String) -> String {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t == "--" { return "--" }
            if t.contains("缓存") { return t }
            return "\(t)·缓存"
        }
        dash.lockStatusText = cache(dash.lockStatusText)
        dash.doorStatusText = cache(dash.doorStatusText)
        dash.windowStatusText = cache(dash.windowStatusText)
        dash.tailgateStatusText = cache(dash.tailgateStatusText)
        dash.driverDoorStatusText = cache(dash.driverDoorStatusText)
        dash.passengerDoorStatusText = cache(dash.passengerDoorStatusText)
        dash.leftRearDoorStatusText = cache(dash.leftRearDoorStatusText)
        dash.rightRearDoorStatusText = cache(dash.rightRearDoorStatusText)
        dash.leftFrontWindowStatusText = cache(dash.leftFrontWindowStatusText)
        dash.rightFrontWindowStatusText = cache(dash.rightFrontWindowStatusText)
        dash.leftRearWindowStatusText = cache(dash.leftRearWindowStatusText)
        dash.rightRearWindowStatusText = cache(dash.rightRearWindowStatusText)
        return dash
    }

    static func preserveBodyStatus(from current: VehicleDashboardState, onto target: VehicleDashboardState) -> VehicleDashboardState {
        var dash = target
        dash.lockStatusText = current.lockStatusText
        dash.doorStatusText = current.doorStatusText
        dash.windowStatusText = current.windowStatusText
        dash.tailgateStatusText = current.tailgateStatusText
        dash.driverDoorStatusText = current.driverDoorStatusText
        dash.passengerDoorStatusText = current.passengerDoorStatusText
        dash.leftRearDoorStatusText = current.leftRearDoorStatusText
        dash.rightRearDoorStatusText = current.rightRearDoorStatusText
        dash.leftFrontWindowStatusText = current.leftFrontWindowStatusText
        dash.rightFrontWindowStatusText = current.rightFrontWindowStatusText
        dash.leftRearWindowStatusText = current.leftRearWindowStatusText
        dash.rightRearWindowStatusText = current.rightRearWindowStatusText
        return dash
    }

    static func stripDashboardBodyCacheSuffix(_ dashboard: VehicleDashboardState) -> VehicleDashboardState {
        var dash = dashboard
        func strip(_ text: String) -> String {
            text.replacingOccurrences(of: "·缓存", with: "")
        }
        dash.lockStatusText = strip(dash.lockStatusText)
        dash.doorStatusText = strip(dash.doorStatusText)
        dash.windowStatusText = strip(dash.windowStatusText)
        dash.tailgateStatusText = strip(dash.tailgateStatusText)
        dash.driverDoorStatusText = strip(dash.driverDoorStatusText)
        dash.passengerDoorStatusText = strip(dash.passengerDoorStatusText)
        dash.leftRearDoorStatusText = strip(dash.leftRearDoorStatusText)
        dash.rightRearDoorStatusText = strip(dash.rightRearDoorStatusText)
        dash.leftFrontWindowStatusText = strip(dash.leftFrontWindowStatusText)
        dash.rightFrontWindowStatusText = strip(dash.rightFrontWindowStatusText)
        dash.leftRearWindowStatusText = strip(dash.leftRearWindowStatusText)
        dash.rightRearWindowStatusText = strip(dash.rightRearWindowStatusText)
        return dash
    }

    /// 自动轮询日志用：只关心用户能感知的车况变化
    func httpPollStatusFingerprint() -> String {
        [
            dashboard.lockStatusText,
            dashboard.doorStatusText,
            dashboard.windowStatusText,
            dashboard.tailgateStatusText,
            dashboard.driverDoorStatusText,
            dashboard.passengerDoorStatusText,
            dashboard.leftRearDoorStatusText,
            dashboard.rightRearDoorStatusText,
            dashboard.leftFrontWindowStatusText,
            dashboard.rightFrontWindowStatusText,
            dashboard.leftRearWindowStatusText,
            dashboard.rightRearWindowStatusText,
            dashboard.acTemperatureText,
            dashboard.batteryPercentValue.map(String.init) ?? "--",
            dashboard.chargingStatusText,
            dashboard.speedText,
            state.online ? "1" : "0",
            state.locked.map { $0 ? "1" : "0" } ?? "-"
        ].joined(separator: "|")
    }

}
