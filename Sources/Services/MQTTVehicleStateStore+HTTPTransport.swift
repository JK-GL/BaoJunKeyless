import Foundation

extension MQTTVehicleStateStore {
    func startHTTPPolling(immediate: Bool) {
        httpTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollHTTPOnce(userInitiated: false, completion: nil)
        }
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
                    let newState = self.mapHTTPToVehicleState(refreshResult.carStatus)
                    var newDashboard = self.mapHTTPToDashboard(refreshResult.carStatus)
                    if !refreshResult.tirePressure.isEmpty {
                        newDashboard = VehicleStatusMapper.tirePressureDashboard(
                            from: refreshResult.tirePressure,
                            base: newDashboard
                        )
                    }
                    let shouldUseHTTP = self.lastMQTTUpdate.map { Date().timeIntervalSince($0) >= 60 } ?? true

                    self.mergeHTTPBaseState(newState: newState, dashboard: newDashboard)
                    if shouldUseHTTP {
                        self.apply(newState)
                        self.applyDashboard(newDashboard)
                    }

                    self.applyHTTPMeta(carInfo: refreshResult.carInfo, carStatus: refreshResult.carStatus)
                    CrashLogger.shared.mark("HTTP", "status updated")

                    let source = shouldUseHTTP ? "HTTP" : "HTTP(已合并，展示仍偏 MQTT)"
                    let message = "车况已更新 · \(source) · \(formatTime(refreshResult.fetchedAt))"
                    if userInitiated {
                        self.vehicleEventLogStore.add(.action, "车况刷新成功", detail: message)
                    }
                    completion?(true, message)

                case .failure(let error):
                    let message = "车况刷新失败：\(error.localizedDescription)"
                    CrashLogger.shared.mark("HTTP", "status refresh failed: \(error.localizedDescription)")
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
}
