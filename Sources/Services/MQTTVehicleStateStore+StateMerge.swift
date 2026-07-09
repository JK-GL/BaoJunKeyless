import Foundation

extension MQTTVehicleStateStore {
    func mergeHTTPBaseState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        let mergedBase = VehicleStateMerger.mergeHTTPBase(current: state, newState: newState)
        let merged = applyLiveBLEOverlay(to: mergedBase)
        apply(merged)

        let dash = VehicleStateMerger.mergeHTTPBaseDashboard(current: dashboard, newDashboard: newDashboard)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    func mergeRealtimeState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: newState)
        let merged = applyLiveBLEOverlay(to: mergedBase)
        apply(merged)

        let dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: newDashboard)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    func applyHTTPMeta(carInfo: [String: String], carStatus: [String: String]) {
        if let coordinate = VehicleHTTPMetaMapper.coordinate(from: carStatus) {
            liveLatitudeGcj = coordinate.latGcj
            liveLongitudeGcj = coordinate.lngGcj
            cachedLatitudeGcj = coordinate.latGcj
            cachedLongitudeGcj = coordinate.lngGcj
            if let addressHint = coordinate.addressHint, !addressHint.isEmpty {
                liveAddress = addressHint
                cachedAddress = addressHint
                persistDisplayCache()
            } else {
                persistDisplayCache()
            }
            locationResolver.getAddress(gcjLat: coordinate.latGcj, gcjLng: coordinate.lngGcj, address: coordinate.addressHint, amapWebKey: addressSettings.amapWebKey) { [weak self] resolved in
                guard let self, let resolved else { return }
                DispatchQueue.main.async {
                    self.liveAddress = resolved
                    self.cachedAddress = resolved
                    self.persistDisplayCache()
                }
            }
        }

        let dash = VehicleHTTPMetaMapper.dashboard(base: dashboard, carInfo: carInfo)
        if VehicleHTTPMetaMapper.supportsMQTT(carInfo: carInfo) {
            authStatus = .valid
        }
        applyDashboard(dash)

        let profile = VehicleHTTPMetaMapper.profile(carInfo: carInfo, carStatus: carStatus)
        applyProfile(profile)
    }
}
