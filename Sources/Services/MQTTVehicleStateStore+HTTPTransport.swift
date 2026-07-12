import Foundation

extension MQTTVehicleStateStore {
    func startHTTPPolling(immediate: Bool) {
        httpTimer?.invalidate()
        // 门窗/车锁不能只靠 60s 一轮；有网时提高频率，MQTT 增量到不了也能及时收敛
        let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.pollHTTPOnce(userInitiated: false, completion: nil)
        }
        // 后台/滑动时也尽量触发
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
                    let httpCollect = parseTimestamp(refreshResult.carStatus["collectTime"])
                    // MQTT 车身更新若更新，则 HTTP 旧 collectTime 不覆盖门窗明细
                    let mqttBodyFresh: Bool = {
                        guard let mqttAt = self.lastMQTTBodyCollectAt else { return false }
                        guard let httpAt = httpCollect else {
                            // HTTP 无 collectTime：若 MQTT 30s 内有车身更新，不让 HTTP 冲门窗
                            return Date().timeIntervalSince(mqttAt) < 30
                        }
                        return mqttAt > httpAt
                    }()

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

                    if mqttBodyFresh {
                        // 保留当前 MQTT 门窗明细，只合并非车身/或总锁等可安全字段
                        newDashboard = Self.preserveBodyStatus(from: self.dashboard, onto: newDashboard)
                        if self.state.doorsClosed != nil { newState.doorsClosed = self.state.doorsClosed }
                        if self.state.windowsClosed != nil { newState.windowsClosed = self.state.windowsClosed }
                        if self.state.driverDoorOpen != nil { newState.driverDoorOpen = self.state.driverDoorOpen }
                        if self.state.trunkOpen != nil { newState.trunkOpen = self.state.trunkOpen }
                    }

                    self.mergeHTTPBaseState(newState: newState, dashboard: newDashboard)
                    self.applyHTTPMeta(carInfo: refreshResult.carInfo, carStatus: refreshResult.carStatus)
                    CrashLogger.shared.mark("HTTP", "status updated")

                    let body = bodyFieldsSummary(refreshResult.carStatus)
                    let message = "车况已更新 · HTTP · \(formatTime(refreshResult.fetchedAt)) · 锁=\(self.dashboard.lockStatusText) 门=\(self.dashboard.doorStatusText) 窗=\(self.dashboard.windowStatusText) 尾=\(self.dashboard.tailgateStatusText) · 主驾=\(self.dashboard.driverDoorStatusText)/副驾=\(self.dashboard.passengerDoorStatusText)/左后=\(self.dashboard.leftRearDoorStatusText)/右后=\(self.dashboard.rightRearDoorStatusText)\(mqttBodyFresh ? " · 保留MQTT车身" : "")\(body.isEmpty ? "" : " · raw:\(body)")"
                    if userInitiated {
                        self.vehicleEventLogStore.add(.action, "车况刷新成功", detail: message)
                    } else {
                        self.vehicleEventLogStore.addThrottled(
                            .action,
                            "车况轮询更新",
                            detail: message,
                            identity: "http-poll-body",
                            minimumInterval: 10
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
}
