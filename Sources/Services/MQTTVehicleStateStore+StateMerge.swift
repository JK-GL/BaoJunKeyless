import Foundation

enum VehicleHTTPMergeMode: String {
    /// 手动刷新：HTTP 全量实时落地
    case full = "全量"
    /// 自动轮询：HTTP 纠正 MQTT 未刚变的字段
    case fillMissingPreferNewer = "字段补齐"
}

extension MQTTVehicleStateStore {
    /// MQTT 字段值刚变化后的短保护，避免半包抖动；过后 HTTP 必须能纠正
    static let mqttFieldHoldSeconds: TimeInterval = 5
    /// BLE 本地锁/解锁保护
    static let localLockHoldSeconds: TimeInterval = 15

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
        var dash = Self.stripDashboardBodyCacheSuffix(dashboard)
        var merged = state
        var filled: [String] = []
        var kept: [String] = []

        func isProtectedByLocalLock(_ key: String) -> Bool {
            guard key == "doorLockStatus" else { return false }
            guard let until = localDoorLockHoldUntil else { return false }
            return now < until
        }

        func isProtectedByRecentMQTT(_ key: String) -> Bool {
            // 手动全量：只认本地锁保护，必须实时纠正
            if mode == .full { return false }
            guard let fieldAt = fieldCollectAt[key] else { return false }
            guard fieldSource[key] == "MQTT" else { return false }
            return now.timeIntervalSince(fieldAt) < Self.mqttFieldHoldSeconds
        }

        func canTake(_ key: String, httpHasValue: Bool) -> Bool {
            guard httpHasValue else { return false }
            if isProtectedByLocalLock(key) { return false }
            if isProtectedByRecentMQTT(key) { return false }
            return true
        }

        func takeText(_ key: String, current: String, incoming: String) -> String {
            let v = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v == "--" { return current }
            if canTake(key, httpHasValue: true) {
                let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if v != cur {
                    filled.append("\(key):\(cur)→\(v)")
                } else {
                    filled.append(key)
                }
                fieldCollectAt[key] = collectAt
                fieldSource[key] = "HTTP"
                return v
            }
            kept.append(key)
            return current
        }

        // 全部实时车身字段
        dash.lockStatusText = takeText("doorLockStatus", current: dash.lockStatusText, incoming: newDashboard.lockStatusText)
        dash.driverDoorStatusText = takeText("door1OpenStatus", current: dash.driverDoorStatusText, incoming: newDashboard.driverDoorStatusText)
        dash.passengerDoorStatusText = takeText("door2OpenStatus", current: dash.passengerDoorStatusText, incoming: newDashboard.passengerDoorStatusText)
        dash.leftRearDoorStatusText = takeText("door3OpenStatus", current: dash.leftRearDoorStatusText, incoming: newDashboard.leftRearDoorStatusText)
        dash.rightRearDoorStatusText = takeText("door4OpenStatus", current: dash.rightRearDoorStatusText, incoming: newDashboard.rightRearDoorStatusText)
        dash.tailgateStatusText = takeText("tailDoorOpenStatus", current: dash.tailgateStatusText, incoming: newDashboard.tailgateStatusText)
        dash.leftFrontWindowStatusText = takeText("window1Status", current: dash.leftFrontWindowStatusText, incoming: newDashboard.leftFrontWindowStatusText)
        dash.rightFrontWindowStatusText = takeText("window2Status", current: dash.rightFrontWindowStatusText, incoming: newDashboard.rightFrontWindowStatusText)
        dash.leftRearWindowStatusText = takeText("window3Status", current: dash.leftRearWindowStatusText, incoming: newDashboard.leftRearWindowStatusText)
        dash.rightRearWindowStatusText = takeText("window4Status", current: dash.rightRearWindowStatusText, incoming: newDashboard.rightRearWindowStatusText)

        let doorRe = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        if doorRe == "全关" || doorRe == "未关" {
            dash.doorStatusText = doorRe
        } else {
            dash.doorStatusText = takeText("doorOpenStatus", current: dash.doorStatusText, incoming: newDashboard.doorStatusText)
        }
        let winRe = VehicleStatusMapper.recomputeWindowStatusText(from: dash)
        if winRe == "全关" || winRe == "未关" {
            dash.windowStatusText = winRe
        } else {
            dash.windowStatusText = takeText("windowStatus", current: dash.windowStatusText, incoming: newDashboard.windowStatusText)
        }

        // 电量/空调/里程/充电/灯光/车速 等全部实时字段
        if canTake("batterySoc", httpHasValue: newDashboard.batteryPercentValue != nil) {
            dash.batteryPercentValue = newDashboard.batteryPercentValue
            if newDashboard.batteryRemainingText != "--" { dash.batteryRemainingText = newDashboard.batteryRemainingText }
            if newDashboard.batteryHealthPercentText != "--" { dash.batteryHealthPercentText = newDashboard.batteryHealthPercentText }
            if newDashboard.batteryVoltageText != "--" { dash.batteryVoltageText = newDashboard.batteryVoltageText }
            if newDashboard.batteryAuxText != "--" { dash.batteryAuxText = newDashboard.batteryAuxText }
            fieldCollectAt["batterySoc"] = collectAt
            fieldSource["batterySoc"] = "HTTP"
            filled.append("batterySoc")
        } else if newDashboard.batteryPercentValue != nil {
            kept.append("batterySoc")
        }

        if canTake("acStatus", httpHasValue: newDashboard.acTemperatureText != "--") {
            dash.acTemperatureText = newDashboard.acTemperatureText
            fieldCollectAt["acStatus"] = collectAt
            fieldSource["acStatus"] = "HTTP"
            filled.append("acStatus")
        }
        if newDashboard.cabinTemperatureText != "--", canTake("interiorTemperature", httpHasValue: true) {
            dash.cabinTemperatureText = newDashboard.cabinTemperatureText
            fieldCollectAt["interiorTemperature"] = collectAt
            fieldSource["interiorTemperature"] = "HTTP"
        }
        if newDashboard.batteryTemperatureText != "--" { dash.batteryTemperatureText = newDashboard.batteryTemperatureText }
        if newDashboard.motorTemperatureText != "--" { dash.motorTemperatureText = newDashboard.motorTemperatureText }
        if newDashboard.inverterTemperatureText != "--" { dash.inverterTemperatureText = newDashboard.inverterTemperatureText }

        if newDashboard.electricRangeKm > 0, canTake("leftMileage", httpHasValue: true) {
            dash.electricRangeKm = newDashboard.electricRangeKm
            if newDashboard.electricFullRangeKm > 0 { dash.electricFullRangeKm = newDashboard.electricFullRangeKm }
            fieldCollectAt["leftMileage"] = collectAt
            fieldSource["leftMileage"] = "HTTP"
        }
        if newDashboard.fuelRangeKm > 0, canTake("oilLeftMileage", httpHasValue: true) {
            dash.fuelRangeKm = newDashboard.fuelRangeKm
            if newDashboard.fuelFullRangeKm > 0 { dash.fuelFullRangeKm = newDashboard.fuelFullRangeKm }
            fieldCollectAt["oilLeftMileage"] = collectAt
            fieldSource["oilLeftMileage"] = "HTTP"
        }
        if newDashboard.fuelPercentValue != nil { dash.fuelPercentValue = newDashboard.fuelPercentValue }
        if newDashboard.fuelRemainingText != "--" { dash.fuelRemainingText = newDashboard.fuelRemainingText }

        if newDashboard.totalMileageText != "--", canTake("mileage", httpHasValue: true) {
            dash.totalMileageText = newDashboard.totalMileageText
            fieldCollectAt["mileage"] = collectAt
            fieldSource["mileage"] = "HTTP"
        }
        if newDashboard.yesterdayMileageText != "--" { dash.yesterdayMileageText = newDashboard.yesterdayMileageText }
        if newDashboard.averageFuelConsumptionText != "--", canTake("avgFuel", httpHasValue: true) {
            dash.averageFuelConsumptionText = newDashboard.averageFuelConsumptionText
            fieldCollectAt["avgFuel"] = collectAt
            fieldSource["avgFuel"] = "HTTP"
        }
        if newDashboard.averagePowerConsumptionText != "--" {
            dash.averagePowerConsumptionText = newDashboard.averagePowerConsumptionText
        }

        if newDashboard.chargingStatusText != "--", canTake("charging", httpHasValue: true) {
            dash.chargingStatusText = newDashboard.chargingStatusText
            dash.isCharging = (newDashboard.chargingStatusText == "是")
            fieldCollectAt["charging"] = collectAt
            fieldSource["charging"] = "HTTP"
        }
        if newDashboard.chargingPowerText != "--", canTake("chargePower", httpHasValue: true) {
            dash.chargingPowerText = newDashboard.chargingPowerText
            dash.chargingPowerValueText = newDashboard.chargingPowerValueText
            fieldCollectAt["chargePower"] = collectAt
            fieldSource["chargePower"] = "HTTP"
        }
        if newDashboard.chargingStateText != "--" { dash.chargingStateText = newDashboard.chargingStateText }
        if newDashboard.obcCurrentText != "--" { dash.obcCurrentText = newDashboard.obcCurrentText }
        if newDashboard.obcTemperatureText != "--" { dash.obcTemperatureText = newDashboard.obcTemperatureText }

        // 胎压
        if newDashboard.leftFrontTirePressureText != "--" { dash.leftFrontTirePressureText = newDashboard.leftFrontTirePressureText }
        if newDashboard.rightFrontTirePressureText != "--" { dash.rightFrontTirePressureText = newDashboard.rightFrontTirePressureText }
        if newDashboard.leftRearTirePressureText != "--" { dash.leftRearTirePressureText = newDashboard.leftRearTirePressureText }
        if newDashboard.rightRearTirePressureText != "--" { dash.rightRearTirePressureText = newDashboard.rightRearTirePressureText }
        if newDashboard.tireTemperatureText != "--" { dash.tireTemperatureText = newDashboard.tireTemperatureText }

        // 灯光 / 车速 / 驾驶
        if newDashboard.speedText != "--" { dash.speedText = newDashboard.speedText }
        if newDashboard.averageSpeedText != "--" { dash.averageSpeedText = newDashboard.averageSpeedText }
        if newDashboard.steeringAngleText != "--" { dash.steeringAngleText = newDashboard.steeringAngleText }
        if newDashboard.throttlePercentText != "--" { dash.throttlePercentText = newDashboard.throttlePercentText }
        if newDashboard.brakePercentText != "--" { dash.brakePercentText = newDashboard.brakePercentText }
        if newDashboard.lowBeamText != "--" { dash.lowBeamText = newDashboard.lowBeamText }
        if newDashboard.highBeamText != "--" { dash.highBeamText = newDashboard.highBeamText }
        if newDashboard.leftTurnText != "--" { dash.leftTurnText = newDashboard.leftTurnText }
        if newDashboard.rightTurnText != "--" { dash.rightTurnText = newDashboard.rightTurnText }
        if newDashboard.positionLightText != "--" { dash.positionLightText = newDashboard.positionLightText }
        if newDashboard.frontFogText != "--" { dash.frontFogText = newDashboard.frontFogText }

        // state 布尔/基础
        if canTake("doorLockStatus", httpHasValue: newState.locked != nil) { merged.locked = newState.locked }
        if canTake("door1OpenStatus", httpHasValue: newState.driverDoorOpen != nil) { merged.driverDoorOpen = newState.driverDoorOpen }
        if canTake("tailDoorOpenStatus", httpHasValue: newState.trunkOpen != nil) { merged.trunkOpen = newState.trunkOpen }
        if canTake("acStatus", httpHasValue: newState.acOn != nil) { merged.acOn = newState.acOn }
        if canTake("autoGearStatus", httpHasValue: newState.gear != .unknown) { merged.gear = newState.gear }
        if canTake("engineStatus", httpHasValue: newState.power != .unknown) { merged.power = newState.power }
        if canTake("keyStatus", httpHasValue: newState.physicalKeyPosition != .unknown) { merged.physicalKeyPosition = newState.physicalKeyPosition }
        if canTake("batterySoc", httpHasValue: newState.fuelLevel != nil) { merged.fuelLevel = newState.fuelLevel }
        if canTake("leftMileage", httpHasValue: newState.fuelRange != nil) { merged.fuelRange = newState.fuelRange }
        if canTake("oilLeftMileage", httpHasValue: newState.oilRange != nil) { merged.oilRange = newState.oilRange }
        if newState.speed != nil { merged.speed = newState.speed }
        if newState.doorsClosed != nil, canTake("doorOpenStatus", httpHasValue: true) || canTake("door1OpenStatus", httpHasValue: true) {
            merged.doorsClosed = newState.doorsClosed
        }
        if newState.windowsClosed != nil, canTake("windowStatus", httpHasValue: true) || canTake("window1Status", httpHasValue: true) {
            merged.windowsClosed = newState.windowsClosed
        }
        merged.online = true
        merged.timestamp = max(merged.timestamp, newState.timestamp, collectAt)

        syncBooleans(from: dash, into: &merged)
        dash.updatedAt = max(dash.updatedAt, collectAt, now)
        dash.updatedAtText = formatTime(dash.updatedAt)
        lastHTTPBodyCollectAt = collectAt
        bumpStatusRevision()

        merged = applyLiveBLEOverlay(to: merged)
        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)

        var noteParts: [String] = []
        if mode == .full { noteParts.append("手动全量") }
        if !filled.isEmpty {
            noteParts.append("补\(min(filled.count, 8))项")
            noteParts.append(filled.prefix(6).joined(separator: ","))
        }
        if !kept.isEmpty { noteParts.append("保留\(min(kept.count, 6))项") }
        if filled.isEmpty && kept.isEmpty { noteParts.append("无变化") }
        if isProtectedByLocalLock("doorLockStatus") { noteParts.append("本地锁保护中") }
        return noteParts.joined(separator: "/")
    }

    /// MQTT 半包：只更新本包字段；只给“值真变了”的字段打时间戳
    func mergeRealtimeState(
        newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        sourceFields: [String: String] = [:],
        collectAt: Date? = nil,
        changedKeys: Set<String> = []
    ) {
        let at = collectAt ?? parseTimestamp(sourceFields["collectTime"]) ?? Date()
        let now = Date()

        var safeState = newState
        var safeDash = newDashboard
        // BLE 本地锁保护窗内，MQTT 门锁不覆盖
        if let until = localDoorLockHoldUntil, now < until {
            safeState.locked = nil
            safeDash.lockStatusText = "--"
        }

        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: safeState)
        var dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: safeDash)
        dash = Self.stripDashboardBodyCacheSuffix(dash)
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)
        dash.updatedAt = max(dash.updatedAt, at, now)
        dash.updatedAtText = formatTime(dash.updatedAt)

        var merged = applyLiveBLEOverlay(to: mergedBase)
        syncBooleans(from: dash, into: &merged)

        // 只给值变化字段打戳；半包旧值重复出现不再刷新时间
        let stampKeys: Set<String> = changedKeys.isEmpty ? Set(sourceFields.keys) : changedKeys
        for key in stampKeys where sourceFields[key] != nil {
            // collectTime 本身不算“车身字段变化”
            if key == "collectTime" { continue }
            fieldCollectAt[key] = at
            fieldSource[key] = "MQTT"
        }
        if stampKeys.contains(where: {
            $0.hasPrefix("door") || $0.hasPrefix("window") || $0.hasPrefix("tailDoor") || $0 == "doorLockStatus" || $0 == "acStatus"
        }) {
            lastMQTTBodyCollectAt = at
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
        "charging", "chargePower", "interiorTemperature", "keyStatus", "autoGearStatus", "engineStatus"
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
