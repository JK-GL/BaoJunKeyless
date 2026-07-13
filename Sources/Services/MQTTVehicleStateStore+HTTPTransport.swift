import Foundation

extension MQTTVehicleStateStore {
    /// MQTT 在线新鲜时慢轮询；断线/过期时快轮询全量
    static let httpPollIntervalMQTTFresh: TimeInterval = 20
    static let httpPollIntervalMQTTStale: TimeInterval = 3
    /// 后台：MQTT 新鲜 / 断旧
    static let httpPollIntervalBackgroundMQTTFresh: TimeInterval = 90
    static let httpPollIntervalBackgroundMQTTStale: TimeInterval = 25
    /// 后台且关闭状态同步：更低频兜底
    static let httpPollIntervalBackgroundSyncOffFresh: TimeInterval = 180
    static let httpPollIntervalBackgroundSyncOffStale: TimeInterval = 60
    /// MQTT 在此时间内有消息，视为新鲜
    static let mqttFreshWindow: TimeInterval = 60

    func isMQTTRealtimeFresh(now: Date = Date()) -> Bool {
        guard mqttStatus == .connected else { return false }
        guard let last = lastMQTTUpdate else { return false }
        return now.timeIntervalSince(last) <= Self.mqttFreshWindow
    }

    func currentHTTPPollInterval(now: Date = Date()) -> TimeInterval {
        let fresh = isMQTTRealtimeFresh(now: now)
        if isAppInForeground {
            return fresh ? Self.httpPollIntervalMQTTFresh : Self.httpPollIntervalMQTTStale
        }
        // 后台
        if keylessSettingsStore.settings.backgroundStateSyncEnabled {
            return fresh ? Self.httpPollIntervalBackgroundMQTTFresh : Self.httpPollIntervalBackgroundMQTTStale
        }
        return fresh ? Self.httpPollIntervalBackgroundSyncOffFresh : Self.httpPollIntervalBackgroundSyncOffStale
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

        CrashLogger.shared.mark(
            "BG",
            "applyRuntime \(reason) fg=\(isAppInForeground ? 1 : 0) sync=\(settings.backgroundStateSyncEnabled ? 1 : 0) keyless=\(settings.keylessEnabled ? 1 : 0) interval=\(Int(interval))"
        )

        // 用户可见：与轮询/扫描一样可 ×N 合并
        vehicleEventLogStore.addCoalesced(
            .system,
            "后台状态同步",
            detail: "\(modeText) · \(backgroundReasonText(reason))",
            identity: "bg-state-sync|\(isAppInForeground ? "fg" : "bg")|\(settings.backgroundStateSyncEnabled ? 1 : 0)|\(Int(interval))",
            mergeWindow: 180
        )

        // 始终用当前策略重挂 HTTP 定时器（前台 20/3，后台 90/25 或更慢）
        if credentialsStore.accessToken.isEmpty {
            httpTimer?.invalidate()
            httpTimer = nil
            return
        }
        startHTTPPolling(immediate: false)

        // 后台且允许状态同步时，尽量保持 MQTT
        if !isAppInForeground && settings.backgroundStateSyncEnabled && settings.keylessEnabled {
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
        // 动态频率：前台 MQTT 新鲜 20s / 断旧 3s；后台自动降频
        let interval = currentHTTPPollInterval()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 后台关闭状态同步时仍允许极低频兜底，但不做 immediate 狂刷
            self.pollHTTPOnce(userInitiated: false, completion: nil)
            // 根据 MQTT / 前后台状态自适应下一次间隔
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

        if userInitiated {
            vehicleEventLogStore.add(.action, "车况刷新开始", detail: "正在请求 queryDefaultCarStatus")
        }

        VehicleHTTPRefreshRequester.shared.fetch(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let refreshResult):
                    self.lastHTTPUpdate = refreshResult.fetchedAt
                    let httpCollect = parseTimestamp(refreshResult.carStatus["collectTime"]) ?? refreshResult.fetchedAt
                    self.lastHTTPBodyCollectAt = httpCollect

                    // 字段级合并（推荐方案）：
                    // - 手动刷新：HTTP 全量落地
                    // - 自动轮询：HTTP 只补“MQTT 没覆盖到 / 或 HTTP 更新的字段”
                    // 不再“MQTT 新鲜就整包忽略 HTTP”，否则门窗会卡到手动刷新才对
                    self.applyHTTPMeta(carInfo: refreshResult.carInfo, carStatus: refreshResult.carStatus)

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

                    let mergeMode: VehicleHTTPMergeMode = {
                        if userInitiated { return .full }
                        // 官方思路：MQTT 新鲜时 HTTP 不冲实时车身；断/旧才全量
                        return self.isMQTTRealtimeFresh() ? .pollMeta : .pollFull
                    }()
                    let mergeNote = self.mergeHTTPBaseState(
                        newState: newState,
                        dashboard: newDashboard,
                        mode: mergeMode,
                        httpCollectAt: httpCollect,
                        sourceFields: refreshResult.carStatus
                    )
                    CrashLogger.shared.mark("HTTP", "status updated mode=\(mergeMode.rawValue)")

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
                    completion?(true, message)

                case .failure(let error):
                    let message = "车况刷新失败：\(error.localizedDescription)"
                    CrashLogger.shared.mark("HTTP", "status refresh failed: \(error.localizedDescription)")
                    // 网络失败时明确离线，避免旧门窗/车锁继续被当成“实时真实状态”
                    self.markVehicleStatusOffline(reason: error.localizedDescription, userInitiated: userInitiated)
                    if userInitiated {
                        self.vehicleEventLogStore.add(.error, "车况刷新失败", detail: message)
                    }
                    completion?(false, message)
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

    /// 车况拉失败时：标记离线；若状态已过期，清掉门窗等“开闭态”避免 UI/无感继续当真。
    /// 车锁 `locked` 若刚被 BLE 本地回写（timestamp 很新）则保留。
    func markVehicleStatusOffline(reason: String, userInitiated: Bool) {
        let now = Date()
        let mqttFresh = lastMQTTUpdate.map { now.timeIntervalSince($0) < 90 } ?? false
        if mqttFresh {
            // MQTT 仍在实时推，只标 online 逻辑由 MQTT 路径维护
            return
        }

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
