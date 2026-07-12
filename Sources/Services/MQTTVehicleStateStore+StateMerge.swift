import Foundation

enum VehicleHTTPMergeMode: String {
    /// 手动刷新：HTTP 全量覆盖车身
    case full = "全量"
    /// 自动轮询：只补 MQTT 缺失/过期字段
    case fillMissingPreferNewer = "字段补齐"
}

extension MQTTVehicleStateStore {
    @discardableResult
    func mergeHTTPBaseState(
        newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        mode: VehicleHTTPMergeMode = .full,
        httpCollectAt: Date? = nil,
        sourceFields: [String: String] = [:]
    ) -> String {
        let collectAt = httpCollectAt ?? Date()
        var noteParts: [String] = []

        if mode == .full {
            // 手动刷新：全量落地
            let mergedBase = VehicleStateMerger.mergeHTTPBase(current: state, newState: newState)
            var dash = VehicleStateMerger.mergeHTTPBaseDashboard(current: dashboard, newDashboard: newDashboard)
            dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
            dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)

            var merged = applyLiveBLEOverlay(to: mergedBase)
            syncBooleans(from: dash, into: &merged)

            // 全量刷新后，相关字段时间戳都记为 HTTP
            for key in Self.bodyFieldKeys {
                if sourceFields[key] != nil || mode == .full {
                    fieldCollectAt[key] = collectAt
                }
            }
            // 即使 source 没给某些总览字段，也刷新门窗总览时间
            fieldCollectAt["doorOpenStatus"] = collectAt
            fieldCollectAt["windowStatus"] = collectAt
            fieldCollectAt["doorLockStatus"] = collectAt
            fieldCollectAt["tailDoorOpenStatus"] = collectAt

            apply(merged)
            applyDashboard(dash)
            evaluateKeylessAutomation(for: merged)
            return "手动全量"
        }

        // 自动：字段级补齐
        var dash = dashboard
        var merged = state
        var filled: [String] = []
        var keptMQTT: [String] = []

        func canTake(_ key: String, httpHasValue: Bool) -> Bool {
            guard httpHasValue else { return false }
            // 该字段从未被 MQTT/HTTP 单独打戳：允许 HTTP 补
            // 典型：MQTT 只推 window2/3，门字段只能靠 HTTP 收敛
            guard let fieldAt = fieldCollectAt[key] else {
                return true
            }
            // 同字段：HTTP collectTime 不旧于该字段最近时间，才覆盖
            return collectAt >= fieldAt
        }

        func takeText(_ key: String, current: String, incoming: String) -> String {
            let v = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v == "--" {
                return current
            }
            // 当前为空/--：直接补
            let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if cur.isEmpty || cur == "--" || cur.contains("缓存") {
                if canTake(key, httpHasValue: true) {
                    fieldCollectAt[key] = collectAt
                    filled.append(key)
                    return v
                }
                keptMQTT.append(key)
                return current
            }
            // 当前已有值：仅当 HTTP 不旧才覆盖（用于门从开到关等收敛）
            if canTake(key, httpHasValue: true) {
                if v != cur {
                    filled.append("\(key):\(cur)→\(v)")
                } else {
                    filled.append(key)
                }
                fieldCollectAt[key] = collectAt
                return v
            }
            keptMQTT.append(key)
            return current
        }

        // 车身明细
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

        // 总览按明细重算；若明细不足再考虑 HTTP 总字段
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

        // 非门窗实时字段：电量/空调/里程等，同样字段级
        if canTake("batterySoc", httpHasValue: newDashboard.batteryPercentValue != nil) {
            dash.batteryPercentValue = newDashboard.batteryPercentValue
            if newDashboard.batteryRemainingText != "--" { dash.batteryRemainingText = newDashboard.batteryRemainingText }
            fieldCollectAt["batterySoc"] = collectAt
            filled.append("batterySoc")
        }
        if canTake("acStatus", httpHasValue: newDashboard.acTemperatureText != "--") {
            dash.acTemperatureText = newDashboard.acTemperatureText
            fieldCollectAt["acStatus"] = collectAt
            filled.append("acStatus")
        }
        if newDashboard.cabinTemperatureText != "--", canTake("interiorTemperature", httpHasValue: true) {
            dash.cabinTemperatureText = newDashboard.cabinTemperatureText
            fieldCollectAt["interiorTemperature"] = collectAt
        }
        if newDashboard.electricRangeKm > 0, canTake("leftMileage", httpHasValue: true) {
            dash.electricRangeKm = newDashboard.electricRangeKm
            fieldCollectAt["leftMileage"] = collectAt
        }
        if newDashboard.fuelRangeKm > 0, canTake("oilLeftMileage", httpHasValue: true) {
            dash.fuelRangeKm = newDashboard.fuelRangeKm
            fieldCollectAt["oilLeftMileage"] = collectAt
        }
        if newDashboard.totalMileageText != "--", canTake("mileage", httpHasValue: true) {
            dash.totalMileageText = newDashboard.totalMileageText
            fieldCollectAt["mileage"] = collectAt
        }
        if newDashboard.averageFuelConsumptionText != "--", canTake("avgFuel", httpHasValue: true) {
            dash.averageFuelConsumptionText = newDashboard.averageFuelConsumptionText
            fieldCollectAt["avgFuel"] = collectAt
        }
        if newDashboard.chargingStatusText != "--", canTake("charging", httpHasValue: true) {
            dash.chargingStatusText = newDashboard.chargingStatusText
            dash.isCharging = (newDashboard.chargingStatusText == "是")
            fieldCollectAt["charging"] = collectAt
        }
        if newDashboard.chargingPowerText != "--", canTake("chargePower", httpHasValue: true) {
            dash.chargingPowerText = newDashboard.chargingPowerText
            dash.chargingPowerValueText = newDashboard.chargingPowerValueText
            fieldCollectAt["chargePower"] = collectAt
        }

        // 胎压通常 HTTP 更全，直接补
        if newDashboard.leftFrontTirePressureText != "--" { dash.leftFrontTirePressureText = newDashboard.leftFrontTirePressureText }
        if newDashboard.rightFrontTirePressureText != "--" { dash.rightFrontTirePressureText = newDashboard.rightFrontTirePressureText }
        if newDashboard.leftRearTirePressureText != "--" { dash.leftRearTirePressureText = newDashboard.leftRearTirePressureText }
        if newDashboard.rightRearTirePressureText != "--" { dash.rightRearTirePressureText = newDashboard.rightRearTirePressureText }
        if newDashboard.tireTemperatureText != "--" { dash.tireTemperatureText = newDashboard.tireTemperatureText }

        // state 布尔/基础字段
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
        merged.online = true
        merged.timestamp = max(merged.timestamp, newState.timestamp)

        // 明细回写总览布尔
        syncBooleans(from: dash, into: &merged)
        dash.updatedAt = max(dash.updatedAt, collectAt)
        dash.updatedAtText = formatTime(dash.updatedAt)

        merged = applyLiveBLEOverlay(to: merged)
        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)

        if !filled.isEmpty {
            noteParts.append("补\(min(filled.count, 8))项")
        }
        if !keptMQTT.isEmpty {
            noteParts.append("保留MQTT\(min(keptMQTT.count, 6))项")
        }
        if filled.isEmpty && keptMQTT.isEmpty {
            noteParts.append("无变化")
        }
        // 精简明细，避免日志过长
        let filledPreview = filled.prefix(6).joined(separator: ",")
        if !filledPreview.isEmpty {
            noteParts.append(filledPreview)
        }
        return noteParts.joined(separator: "/")
    }

    func mergeRealtimeState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState, sourceFields: [String: String] = [:], collectAt: Date? = nil) {
        let at = collectAt ?? parseTimestamp(sourceFields["collectTime"]) ?? Date()
        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: newState)
        var dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: newDashboard)
        // 用明细重算总览，避免半包把“全关/未关”钉死
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)

        var merged = applyLiveBLEOverlay(to: mergedBase)
        syncBooleans(from: dash, into: &merged)

        // 记录 MQTT 实际推到的字段时间，供 HTTP 字段级合并判断
        let keys = sourceFields.keys.isEmpty ? Self.bodyFieldKeys : Array(sourceFields.keys)
        for key in keys {
            // 只给“本包确实带了”的字段打戳
            if sourceFields[key] != nil {
                fieldCollectAt[key] = at
            }
        }
        // 若本包改了明细，总览也跟着记 MQTT 时间
        if sourceFields.keys.contains(where: { $0.hasPrefix("door") || $0.hasPrefix("window") || $0.hasPrefix("tailDoor") || $0 == "doorLockStatus" }) {
            lastMQTTBodyCollectAt = at
        }

        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    private func syncBooleans(from dash: VehicleDashboardState, into merged: inout VehicleState) {
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
