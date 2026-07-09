import Foundation

extension MQTTVehicleStateStore {
    func startHTTPPolling(immediate: Bool) {
        httpTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollHTTPOnce()
        }
        httpTimer = timer
        if immediate { pollHTTPOnce() }
    }

    private func pollHTTPOnce() {
        let store = credentialsStore
        let token = store.accessToken
        guard !token.isEmpty else { return }

        VehicleHTTPRefreshRequester.shared.fetch(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard case .success(let refreshResult) = result else { return }
                self.lastHTTPUpdate = refreshResult.fetchedAt
                let newState = self.mapHTTPToVehicleState(refreshResult.carStatus)
                var newDashboard = self.mapHTTPToDashboard(refreshResult.carStatus)
                if !refreshResult.tirePressure.isEmpty {
                    newDashboard = VehicleStatusMapper.tirePressureDashboard(from: refreshResult.tirePressure, base: newDashboard)
                }
                let shouldUseHTTP = self.lastMQTTUpdate.map { Date().timeIntervalSince($0) >= 60 } ?? true

                self.mergeHTTPBaseState(newState: newState, dashboard: newDashboard)
                if shouldUseHTTP {
                    self.apply(newState)
                    self.applyDashboard(newDashboard)
                }

                self.applyHTTPMeta(carInfo: refreshResult.carInfo, carStatus: refreshResult.carStatus)
                CrashLogger.shared.mark("HTTP", "status updated")
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
