import Foundation

enum VehicleHTTPMergeMode: String {
    /// 手动刷新：强制全量落地
    case full = "全量"
    /// 自动轮询：collectTime 不旧则全量覆盖车身
    case poll = "轮询全量"
}

extension MQTTVehicleStateStore {
    /// BLE 本地锁/解锁后，网络门锁短保护
    static let localLockHoldSeconds: TimeInterval = 15

    /// 官方同款：
    /// - HTTP：全量车身真相（3s 轮询 / 手动刷新）
    /// - MQTT：只增量本包字段
    /// - 总览：只由四门四窗明细重算
    /// - 不再用字段时间戳互锁卡死 HTTP 纠正
    @discardableResult
    func mergeHTTPBaseState(
        newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        mode: VehicleHTTPMergeMode = .full,
        httpCollectAt: Date? = nil,
        sourceFields: [String: String] = [:]
    ) -> String {
        let collectAt = httpCollectAt ?? Date()
        let now = Date()

        // collectTime 闸门：自动轮询时，更旧的 HTTP 不覆盖车身
        if mode == .poll, let current = bodyCollectTime, collectAt < current {
            return "丢弃旧HTTP"
        }

        var dash = Self.stripDashboardBodyCacheSuffix(newDashboard)
        // 总览强制由明细重算，禁止总字段误伤
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)

        // BLE 本地锁保护窗内，不覆盖门锁
        var mergedState = newState
        if let until = localDoorLockHoldUntil, now < until {
            mergedState.locked = state.locked
            dash.lockStatusText = dashboard.lockStatusText
        }

        var merged = VehicleStateMerger.mergeHTTPBase(current: state, newState: mergedState)
        // 明细权威：用 dashboard 回写布尔
        syncBooleans(from: dash, into: &merged)
        merged.online = true
        merged.timestamp = max(merged.timestamp, collectAt, now)

        dash.updatedAt = max(collectAt, now)
        dash.updatedAtText = formatTime(dash.updatedAt)
        bodyCollectTime = collectAt
        lastHTTPBodyCollectAt = collectAt

        // 全量落地后，清理字段保护痕迹（不再用字段戳卡 HTTP）
        fieldCollectAt.removeAll()
        fieldSource.removeAll()
        // 仅保留 BLE 本地锁戳
        if let until = localDoorLockHoldUntil, now < until {
            fieldCollectAt["doorLockStatus"] = now
            fieldSource["doorLockStatus"] = "BLE"
        }

        bumpStatusRevision()
        merged = applyLiveBLEOverlay(to: merged)
        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)

        if mode == .full {
            return localDoorLockHoldUntil.map { now < $0 ? "手动全量/本地锁保护中" : "手动全量" } ?? "手动全量"
        }
        return localDoorLockHoldUntil.map { now < $0 ? "轮询全量/本地锁保护中" : "轮询全量" } ?? "轮询全量"
    }

    /// MQTT 半包：只更新本包出现的字段；总览由明细重算
    func mergeRealtimeState(
        newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        sourceFields: [String: String] = [:],
        collectAt: Date? = nil,
        changedKeys: Set<String> = []
    ) {
        let at = collectAt ?? parseTimestamp(sourceFields["collectTime"]) ?? Date()
        let now = Date()

        // 若 MQTT collectTime 明显旧于当前模型，丢弃（防止旧半包回放）
        if let current = bodyCollectTime, at + 0.5 < current {
            return
        }

        var safeState = newState
        var safeDash = newDashboard
        if let until = localDoorLockHoldUntil, now < until {
            safeState.locked = nil
            safeDash.lockStatusText = "--"
        }

        // mergeRealtime* 已是“有值才覆盖”
        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: safeState)
        var dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: safeDash)
        dash = Self.stripDashboardBodyCacheSuffix(dash)
        // 关键：总览只由明细重算，绝不让半包总字段把门2/3/4刷开
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)
        dash.updatedAt = max(dash.updatedAt, at, now)
        dash.updatedAtText = formatTime(dash.updatedAt)

        var merged = applyLiveBLEOverlay(to: mergedBase)
        syncBooleans(from: dash, into: &merged)
        bodyCollectTime = max(bodyCollectTime ?? at, at)
        lastMQTTBodyCollectAt = at

        // 仅记录变化字段来源（日志用），不再用于卡 HTTP
        for key in changedKeys where sourceFields[key] != nil && key != "collectTime" {
            fieldCollectAt[key] = at
            fieldSource[key] = "MQTT"
        }

        bumpStatusRevision()
        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    private func syncBooleans(from dash: VehicleDashboardState, into merged: inout VehicleState) {
        if dash.doorStatusText == "全关" || dash.doorStatusText.hasPrefix("全关") { merged.doorsClosed = true }
        else if dash.doorStatusText == "未关" || dash.doorStatusText.hasPrefix("未关") { merged.doorsClosed = false }
        if dash.windowStatusText == "全关" || dash.windowStatusText.hasPrefix("全关") { merged.windowsClosed = true }
        else if dash.windowStatusText == "未关" || dash.windowStatusText.hasPrefix("未关") { merged.windowsClosed = false }
        if dash.tailgateStatusText == "已关" || dash.tailgateStatusText.hasPrefix("已关") { merged.trunkOpen = false }
        else if dash.tailgateStatusText == "已开" || dash.tailgateStatusText.hasPrefix("已开") { merged.trunkOpen = true }
        if dash.driverDoorStatusText == "已关" || dash.driverDoorStatusText.hasPrefix("已关") { merged.driverDoorOpen = false }
        else if dash.driverDoorStatusText == "未关" || dash.driverDoorStatusText.hasPrefix("未关") { merged.driverDoorOpen = true }
        if dash.lockStatusText == "已锁车" || dash.lockStatusText.hasPrefix("已锁") { merged.locked = true }
        else if dash.lockStatusText == "未锁" || dash.lockStatusText.hasPrefix("未锁") { merged.locked = false }
    }

    static let bodyFieldKeys: [String] = [
        "doorLockStatus", "doorOpenStatus",
        "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus", "tailDoorOpenStatus",
        "windowStatus", "window1Status", "window2Status", "window3Status", "window4Status",
        "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
        "acStatus", "batterySoc", "leftMileage", "oilLeftMileage", "mileage", "avgFuel",
        "charging", "chargePower", "interiorTemperature", "keyStatus", "autoGearStatus", "engineStatus",
        "strWhAng", "accActPos", "brakPedalPos", "vehSpd", "speed"
    ]

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
