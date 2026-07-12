import Foundation

extension MQTTVehicleStateStore {
    func mergeHTTPBaseState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        let mergedBase = VehicleStateMerger.mergeHTTPBase(current: state, newState: newState)
        var dash = VehicleStateMerger.mergeHTTPBaseDashboard(current: dashboard, newDashboard: newDashboard)
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)

        var merged = applyLiveBLEOverlay(to: mergedBase)
        if dash.doorStatusText == "全关" { merged.doorsClosed = true }
        else if dash.doorStatusText == "未关" { merged.doorsClosed = false }
        if dash.windowStatusText == "全关" { merged.windowsClosed = true }
        else if dash.windowStatusText == "未关" { merged.windowsClosed = false }
        if dash.tailgateStatusText == "已关" { merged.trunkOpen = false }
        else if dash.tailgateStatusText == "已开" { merged.trunkOpen = true }
        if dash.driverDoorStatusText == "已关" { merged.driverDoorOpen = false }
        else if dash.driverDoorStatusText == "未关" { merged.driverDoorOpen = true }
        if dash.lockStatusText == "已锁车" { merged.locked = true }
        else if dash.lockStatusText == "未锁" { merged.locked = false }

        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    func mergeRealtimeState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: newState)
        var dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: newDashboard)
        // 用明细重算总览，避免半包把“全关/未关”钉死
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)

        var merged = applyLiveBLEOverlay(to: mergedBase)
        // 总览同步回布尔，供无感使用
        if dash.doorStatusText == "全关" { merged.doorsClosed = true }
        else if dash.doorStatusText == "未关" { merged.doorsClosed = false }
        if dash.windowStatusText == "全关" { merged.windowsClosed = true }
        else if dash.windowStatusText == "未关" { merged.windowsClosed = false }
        if dash.tailgateStatusText == "已关" { merged.trunkOpen = false }
        else if dash.tailgateStatusText == "已开" { merged.trunkOpen = true }
        if dash.driverDoorStatusText == "已关" { merged.driverDoorOpen = false }
        else if dash.driverDoorStatusText == "未关" { merged.driverDoorOpen = true }

        apply(merged)
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
