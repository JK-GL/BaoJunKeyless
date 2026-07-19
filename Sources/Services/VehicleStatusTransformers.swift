import Foundation

struct VehicleCoordinateUpdate {
    let latGcj: Double
    let lngGcj: Double
    let addressHint: String?
}

enum VehicleStatusMapper {
    static func httpState(from s: [String: String], base state: VehicleState) -> VehicleState {
        var next = state
        next.timestamp = parseTimestamp(s["collectTime"]) ?? Date()
        next.online = true

        next.locked = parseLocked(s["doorLockStatus"])
        next.doorsClosed = parseDoorClosed(s)
        next.driverDoorOpen = parseOpen(s["door1OpenStatus"])
        next.trunkOpen = parseOpen(s["tailDoorOpenStatus"])
        next.windowsClosed = parseWindowsClosed(s)

        // 油量/油续航只使用燃油字段；batterySoc 不能写进 fuelLevel，
        // 否则纯电车型会被误判成“有油”。
        next.fuelLevel = parseDouble(s["leftFuel"] ?? s["fuelPercent"] ?? s["oilPercent"])
        let oilMileage = parseDouble(s["oilLeftMileage"])
        next.fuelRange = oilMileage
        next.oilRange = oilMileage

        next.acOn = parseACStatus(s["acStatus"])
        // accCntTemp 是空调设定温度；interiorTemperature 是车内温度，不能混用。
        next.acTemperature = parseDouble(s["accCntTemp"])
        next.gear = parseGear(s["autoGearStatus"]) ?? .unknown
        // 本车 HTTP 通常无 engineStatus；缺字段时保留当前粘性电源，不回落 unknown/未确认。
        if let power = parsePowerState(s) {
            next.power = power
        }
        // vehSpdAvgDrvn 是平均车速，不能用于实时车速/无感安全门禁。
        next.speed = parseDouble(s["speed"] ?? s["vehSpd"])
        next.physicalKeyPosition = parsePhysicalKeyPosition(s["keyStatus"])
        // phoneNearby / bleRssi 只由手机侧 live BLE 决定。
        return next
    }

    static func httpDashboard(from s: [String: String], base dashboard: VehicleDashboardState) -> VehicleDashboardState {
        // 每次 HTTP 都从干净仪表快照重建；只保留非车况资料和独立胎压接口结果。
        var d = VehicleDashboardState()
        d.energyType = dashboard.energyType
        d.vehicleName = dashboard.vehicleName
        d.vehicleImageURL = dashboard.vehicleImageURL
        d.vinText = dashboard.vinText
        d.userIdText = dashboard.userIdText
        d.bleMacText = dashboard.bleMacText
        d.keyIdText = dashboard.keyIdText
        d.masterKeyMaskedText = dashboard.masterKeyMaskedText
        d.randomMaskedText = dashboard.randomMaskedText
        d.keyTypeText = dashboard.keyTypeText
        d.keyExpiryText = dashboard.keyExpiryText
        d.vehicleInfoUpdatedAtText = dashboard.vehicleInfoUpdatedAtText
        d.tireTemperatureText = dashboard.tireTemperatureText
        d.leftFrontTirePressureText = dashboard.leftFrontTirePressureText
        d.rightFrontTirePressureText = dashboard.rightFrontTirePressureText
        d.leftRearTirePressureText = dashboard.leftRearTirePressureText
        d.rightRearTirePressureText = dashboard.rightRearTirePressureText
        d.updatedAt = parseTimestamp(s["collectTime"]) ?? Date()
        d.updatedAtText = formatTime(d.updatedAt)

        let electricRange = parseInt(s["leftMileage"]) ?? d.electricRangeKm
        let fuelRange = parseInt(s["oilLeftMileage"]) ?? d.fuelRangeKm
        d.electricRangeKm = electricRange
        d.fuelRangeKm = fuelRange
        d.batteryPercentValue = parseInt(s["batterySoc"])
        d.fuelPercentValue = parseInt(s["fuelPercent"] ?? s["oilPercent"] ?? s["leftFuel"])
        if let batterySoc = parseInt(s["batterySoc"]) { d.electricFullRangeKm = max(electricRange, Int(Double(electricRange) / max(Double(batterySoc), 1) * 100)) }
        if let fuelPercent = d.fuelPercentValue, fuelPercent > 0 {
            d.fuelFullRangeKm = max(fuelRange, Int(Double(fuelRange) / max(Double(fuelPercent), 1) * 100))
        }

        d.batteryRemainingText = displayBatteryRemaining(s, fallback: "--")
        d.batteryHealthPercentText = displayBatteryHealth(s, fallback: "--")
        d.batteryVoltageText = displayValue(s["voltage"], suffix: "V")
        d.batteryAuxText = displayValue(s["lowBatVol"], suffix: "V")

        d.cabinTemperatureText = displayValue(s["interiorTemperature"], suffix: "°C")
        d.acTemperatureText = displayACTemperature(s, fallback: "--")
        d.batteryTemperatureText = displayValue(s["batAvgTemp"] ?? s["batMinTemp"], suffix: "°C")
        d.motorTemperatureText = displayValue(s["tmActTemp"], suffix: "°C")
        d.inverterTemperatureText = displayValue(s["invActTemp"], suffix: "°C")

        let charging = parseCharging(s)
        d.isCharging = charging == true
        d.chargingStatusText = charging.map { $0 ? "是" : "否" } ?? "--"
        // 此车型未充电时会返回 chargePower/obcTemp 空串，而非 0。
        // 明确的 charging=0/vecChrgingSts=0 下按实际状态展示，不能保留成“--”。
        let notCharging = charging == false
        d.chargingPowerText = displayText(s["chargePower"]).map { "\($0) kW" } ?? (notCharging ? "0 kW" : "--")
        d.chargingPowerValueText = displayText(s["chargePower"]).map { "\($0) kW" } ?? (notCharging ? "0 kW" : "--")
        d.obcCurrentText = displayText(s["obcOtpCur"]).map { "\($0)A" } ?? (notCharging ? "0A" : "--")
        d.obcTemperatureText = displayText(s["obcTemp"]).map { "\($0)°C" } ?? (notCharging ? "未充电" : "--")
        d.chargingStateText = displayChargingState(s, isCharging: charging)

        // 只写 HTTP 实际带了的字段；缺字段保持 base，避免把 MQTT 实时门窗刷成 --/全关
        if s["doorLockStatus"] != nil {
            d.lockStatusText = (parseLocked(s["doorLockStatus"]) == true) ? "已锁车" : ((parseLocked(s["doorLockStatus"]) == false) ? "未锁" : d.lockStatusText)
        }
        if s["tailDoorOpenStatus"] != nil {
            d.tailgateStatusText = displayOpenStatus(s["tailDoorOpenStatus"], closedText: "已关", openText: "已开")
        }
        if s["door1OpenStatus"] != nil {
            d.driverDoorStatusText = displayOpenStatus(s["door1OpenStatus"], closedText: "已关", openText: "未关")
        }
        if s["door2OpenStatus"] != nil {
            d.passengerDoorStatusText = displayOpenStatus(s["door2OpenStatus"], closedText: "已关", openText: "未关")
        }
        if s["door3OpenStatus"] != nil {
            d.leftRearDoorStatusText = displayOpenStatus(s["door3OpenStatus"], closedText: "已关", openText: "未关")
        }
        if s["door4OpenStatus"] != nil {
            d.rightRearDoorStatusText = displayOpenStatus(s["door4OpenStatus"], closedText: "已关", openText: "未关")
        }
        if s["window1Status"] != nil || s["window1OpenDegree"] != nil || s["window1HalfOpenStatus"] != nil {
            d.leftFrontWindowStatusText = displayWindowStatus(s["window1Status"], degree: s["window1OpenDegree"], half: s["window1HalfOpenStatus"])
        }
        if s["window2Status"] != nil || s["window2OpenDegree"] != nil || s["window2HalfOpenStatus"] != nil {
            d.rightFrontWindowStatusText = displayWindowStatus(s["window2Status"], degree: s["window2OpenDegree"], half: s["window2HalfOpenStatus"])
        }
        if s["window3Status"] != nil || s["window3OpenDegree"] != nil || s["window3HalfOpenStatus"] != nil {
            d.leftRearWindowStatusText = displayWindowStatus(s["window3Status"], degree: s["window3OpenDegree"], half: s["window3HalfOpenStatus"])
        }
        if s["window4Status"] != nil || s["window4OpenDegree"] != nil || s["window4HalfOpenStatus"] != nil {
            d.rightRearWindowStatusText = displayWindowStatus(s["window4Status"], degree: s["window4OpenDegree"], half: s["window4HalfOpenStatus"])
        }
        // 总览优先明细重算；总字段只在明细不足时兜底
        let recomputedDoors = recomputeDoorStatusText(from: d)
        if recomputedDoors == "未关" || recomputedDoors == "全关" {
            d.doorStatusText = recomputedDoors
        } else if let doorsClosed = parseDoorClosed(s) {
            d.doorStatusText = doorsClosed ? "全关" : "未关"
        }
        let recomputedWindows = recomputeWindowStatusText(from: d)
        if recomputedWindows == "未关" || recomputedWindows == "全关" {
            d.windowStatusText = recomputedWindows
        } else if let windowsClosed = parseWindowsClosed(s) {
            d.windowStatusText = windowsClosed ? "全关" : "未关"
        }
        let leftFrontPressure = firstDisplayTirePressure(s, corner: .leftFront)
        if leftFrontPressure != "--" { d.leftFrontTirePressureText = leftFrontPressure }
        let rightFrontPressure = firstDisplayTirePressure(s, corner: .rightFront)
        if rightFrontPressure != "--" { d.rightFrontTirePressureText = rightFrontPressure }
        let leftRearPressure = firstDisplayTirePressure(s, corner: .leftRear)
        if leftRearPressure != "--" { d.leftRearTirePressureText = leftRearPressure }
        let rightRearPressure = firstDisplayTirePressure(s, corner: .rightRear)
        if rightRearPressure != "--" { d.rightRearTirePressureText = rightRearPressure }
        let tireTemperature = displayTireTemperature([:], fallbackCarStatus: s)
        if tireTemperature != "--" { d.tireTemperatureText = tireTemperature }

        // 日志证实本车型驻车时不下发 speed/vehSpd（平均车速也为空）；P 挡可明确显示 0。
        let isParked = parseGear(s["autoGearStatus"]) == .p
        d.speedText = displayText(s["speed"] ?? s["vehSpd"]).map { "\($0)km/h" } ?? (isParked ? "0km/h" : "--")
        d.averageSpeedText = displayText(s["vehSpdAvgDrvn"]).map { "\($0)km/h" } ?? (isParked ? "0km/h" : "--")
        d.steeringAngleText = displayValue(s["strWhAng"], suffix: "°")
        d.throttlePercentText = displayValue(s["accActPos"], suffix: "%")
        d.brakePercentText = displayValue(s["brakPedalPos"], suffix: "%")
        d.totalMileageText = displayValue(s["mileage"], suffix: "km")
        d.yesterdayMileageText = displayValue(s["yesterMileage"], suffix: "km")
        d.fuelRemainingText = displayFuelRemaining(s, fallback: "--")
        d.averageFuelConsumptionText = displayValue(s["avgFuel"], suffix: "L/100km")
        d.averagePowerConsumptionText = displayPowerConsumption(s, fallback: "--")

        // 灯光字段：dipHeadLight=远光，lowBeamLight=近光。
        d.lowBeamText = displayBool(s["lowBeamLight"])
        d.highBeamText = displayBool(s["dipHeadLight"])
        d.leftTurnText = displayBool(s["leftTurnLight"])
        d.rightTurnText = displayBool(s["rightTurnLight"])
        d.positionLightText = displayBool(s["positionLight"])
        d.frontFogText = displayBool(s["frontFogLight"])
        return d
    }

    static func tirePressureDashboard(from s: [String: String], base dashboard: VehicleDashboardState) -> VehicleDashboardState {
        var d = dashboard
        d.tireTemperatureText = displayTireTemperature(s)
        d.leftFrontTirePressureText = firstDisplayTirePressure(s, corner: .leftFront, preferTirePayload: true)
        d.rightFrontTirePressureText = firstDisplayTirePressure(s, corner: .rightFront, preferTirePayload: true)
        d.leftRearTirePressureText = firstDisplayTirePressure(s, corner: .leftRear, preferTirePayload: true)
        d.rightRearTirePressureText = firstDisplayTirePressure(s, corner: .rightRear, preferTirePayload: true)
        return d
    }

    static func mqttState(from s: [String: String], base state: VehicleState) -> VehicleState {
        var next = state
        next.timestamp = parseTimestamp(s["collectTime"]) ?? Date()
        next.online = true
        if let locked = parseLocked(s["doorLockStatus"]) { next.locked = locked }
        // MQTT 官方字段有值即更新；缺字段/空串不覆盖。
        if let doorsClosed = parseDoorClosed(s) { next.doorsClosed = doorsClosed }
        if let windowsClosed = parseWindowsClosed(s) { next.windowsClosed = windowsClosed }
        if let driverOpen = parseOpen(s["door1OpenStatus"]) { next.driverDoorOpen = driverOpen }
        if let trunkOpen = parseOpen(s["tailDoorOpenStatus"]) { next.trunkOpen = trunkOpen }
        if let ac = parseACStatus(s["acStatus"]) { next.acOn = ac }
        // accCntTemp 是设定温度；interiorTemperature 是车内温度，不能混作空调设定。
        if let temp = parseDouble(s["accCntTemp"]) { next.acTemperature = temp }
        if let gear = parseGear(s["autoGearStatus"]) { next.gear = gear }
        if let power = parsePowerState(s) { next.power = power }
        let keyPos = parsePhysicalKeyPosition(s["keyStatus"])
        if s["keyStatus"] != nil { next.physicalKeyPosition = keyPos }
        if let fuel = parseDouble(s["leftFuel"] ?? s["fuelPercent"] ?? s["oilPercent"]) { next.fuelLevel = fuel }
        if let oilMileage = parseDouble(s["oilLeftMileage"]) {
            next.fuelRange = oilMileage
            next.oilRange = oilMileage
        }
        if let speed = parseDouble(s["speed"] ?? s["vehSpd"]) { next.speed = speed }
        return next
    }

    static func mqttDashboard(from s: [String: String], base dashboard: VehicleDashboardState) -> VehicleDashboardState {
        var d = dashboard
        // 先写明细，再根据“合并后的明细”重算总览，避免半包把 全关/未关 算错
        if let locked = parseLocked(s["doorLockStatus"]) { d.lockStatusText = locked ? "已锁车" : "未锁" }
        if s["tailDoorOpenStatus"] != nil {
            d.tailgateStatusText = displayOpenStatus(s["tailDoorOpenStatus"], closedText: "已关", openText: "已开")
        }
        if s["door1OpenStatus"] != nil { d.driverDoorStatusText = displayOpenStatus(s["door1OpenStatus"], closedText: "已关", openText: "未关") }
        if s["door2OpenStatus"] != nil { d.passengerDoorStatusText = displayOpenStatus(s["door2OpenStatus"], closedText: "已关", openText: "未关") }
        if s["door3OpenStatus"] != nil { d.leftRearDoorStatusText = displayOpenStatus(s["door3OpenStatus"], closedText: "已关", openText: "未关") }
        if s["door4OpenStatus"] != nil { d.rightRearDoorStatusText = displayOpenStatus(s["door4OpenStatus"], closedText: "已关", openText: "未关") }
        if s["window1Status"] != nil || s["window1OpenDegree"] != nil || s["window1HalfOpenStatus"] != nil {
            d.leftFrontWindowStatusText = displayWindowStatus(s["window1Status"], degree: s["window1OpenDegree"], half: s["window1HalfOpenStatus"])
        }
        if s["window2Status"] != nil || s["window2OpenDegree"] != nil || s["window2HalfOpenStatus"] != nil {
            d.rightFrontWindowStatusText = displayWindowStatus(s["window2Status"], degree: s["window2OpenDegree"], half: s["window2HalfOpenStatus"])
        }
        if s["window3Status"] != nil || s["window3OpenDegree"] != nil || s["window3HalfOpenStatus"] != nil {
            d.leftRearWindowStatusText = displayWindowStatus(s["window3Status"], degree: s["window3OpenDegree"], half: s["window3HalfOpenStatus"])
        }
        if s["window4Status"] != nil || s["window4OpenDegree"] != nil || s["window4HalfOpenStatus"] != nil {
            d.rightRearWindowStatusText = displayWindowStatus(s["window4Status"], degree: s["window4OpenDegree"], half: s["window4HalfOpenStatus"])
        }

        // 总览始终按“合并后明细”重算；半包总字段绝不再改写总览
        d.doorStatusText = recomputeDoorStatusText(from: d)
        d.windowStatusText = recomputeWindowStatusText(from: d)
        let leftFrontTirePressure = firstDisplayTirePressure(s, corner: .leftFront)
        if leftFrontTirePressure != "--" { d.leftFrontTirePressureText = leftFrontTirePressure }
        let rightFrontTirePressure = firstDisplayTirePressure(s, corner: .rightFront)
        if rightFrontTirePressure != "--" { d.rightFrontTirePressureText = rightFrontTirePressure }
        let leftRearTirePressure = firstDisplayTirePressure(s, corner: .leftRear)
        if leftRearTirePressure != "--" { d.leftRearTirePressureText = leftRearTirePressure }
        let rightRearTirePressure = firstDisplayTirePressure(s, corner: .rightRear)
        if rightRearTirePressure != "--" { d.rightRearTirePressureText = rightRearTirePressure }
        let tireTemperatureText = displayTireTemperature(s)
        if tireTemperatureText != "--" { d.tireTemperatureText = tireTemperatureText }
        if let ac = parseACStatus(s["acStatus"]) {
            d.acTemperatureText = displayACTemperature(s, fallback: ac ? "开启" : "关闭")
        } else if s["accCntTemp"] != nil || s["interiorTemperature"] != nil {
            d.acTemperatureText = displayACTemperature(s, fallback: d.acTemperatureText)
        }
        if let cabin = s["interiorTemperature"], !cabin.isEmpty {
            d.cabinTemperatureText = displayValue(cabin, suffix: "°C")
        }
        if let soc = parseInt(s["batterySoc"]) {
            d.batteryPercentValue = soc
            d.batteryRemainingText = displayBatteryRemaining(s, fallback: d.batteryRemainingText)
        }
        if s["leftBatteryPower"] != nil {
            d.batteryRemainingText = displayBatteryRemaining(s, fallback: d.batteryRemainingText)
        }
        if s["batSoh"] != nil || s["batSOH"] != nil || s["batHealth"] != nil {
            d.batteryHealthPercentText = displayBatteryHealth(s, fallback: d.batteryHealthPercentText)
        }
        if let voltage = s["voltage"], !voltage.isEmpty { d.batteryVoltageText = displayValue(voltage, suffix: "V") }
        if let lowBat = s["lowBatVol"], !lowBat.isEmpty { d.batteryAuxText = displayValue(lowBat, suffix: "V") }
        if let leftMileage = parseInt(s["leftMileage"]) {
            d.electricRangeKm = leftMileage
        }
        if let fuelRange = parseInt(s["oilLeftMileage"]) {
            d.fuelRangeKm = fuelRange
        }
        if let fuelPercent = parseInt(s["fuelPercent"] ?? s["oilPercent"] ?? s["leftFuel"]) {
            d.fuelPercentValue = fuelPercent
            d.fuelRemainingText = displayFuelRemaining(s, fallback: d.fuelRemainingText)
        }
        if s["charging"] != nil || s["vecChrgingSts"] != nil || s["vecChrgStsIndOn"] != nil || s["wireConnect"] != nil || s["rechargeStatus"] != nil {
            let charging = parseCharging(s)
            if let charging {
                d.isCharging = charging
                d.chargingStatusText = charging ? "是" : "否"
            }
            let chargeState = displayChargingState(s, isCharging: charging)
            if chargeState != "--" { d.chargingStateText = chargeState }
        }
        if let chargePower = s["chargePower"], !chargePower.isEmpty {
            d.chargingPowerText = displayValue(chargePower, suffix: " kW")
            d.chargingPowerValueText = displayValue(chargePower, suffix: " kW")
        }
        if let mileage = s["mileage"], !mileage.isEmpty {
            d.totalMileageText = displayValue(mileage, suffix: "km")
        }
        if let yester = s["yesterMileage"], !yester.isEmpty {
            d.yesterdayMileageText = displayValue(yester, suffix: "km")
        }
        if let avgFuel = s["avgFuel"], !avgFuel.isEmpty {
            d.averageFuelConsumptionText = displayValue(avgFuel, suffix: "L/100km")
        }
        if s["avgElectronFuel"] != nil || s["avgElecFuel"] != nil || s["avgPowerConsumption"] != nil {
            d.averagePowerConsumptionText = displayPowerConsumption(s, fallback: d.averagePowerConsumptionText)
        }
        if let speed = s["speed"] ?? s["vehSpd"], !speed.isEmpty { d.speedText = "\(speed)km/h" }
        if let averageSpeed = s["vehSpdAvgDrvn"], !averageSpeed.isEmpty { d.averageSpeedText = "\(averageSpeed)km/h" }
        if let lowBeam = s["lowBeamLight"] { d.lowBeamText = displayBool(lowBeam) }
        if let highBeam = s["dipHeadLight"] { d.highBeamText = displayBool(highBeam) }
        if let leftTurn = s["leftTurnLight"] { d.leftTurnText = displayBool(leftTurn) }
        if let rightTurn = s["rightTurnLight"] { d.rightTurnText = displayBool(rightTurn) }
        if let position = s["positionLight"] { d.positionLightText = displayBool(position) }
        if let fog = s["frontFogLight"] { d.frontFogText = displayBool(fog) }
        d.updatedAt = parseTimestamp(s["collectTime"]) ?? Date()
        d.updatedAtText = formatTime(d.updatedAt)
        
        if let batT = s["batAvgTemp"] ?? s["batMinTemp"], !batT.isEmpty {
            d.batteryTemperatureText = displayValue(batT, suffix: "°C")
        }
        if let motorT = s["tmActTemp"], !motorT.isEmpty { d.motorTemperatureText = displayValue(motorT, suffix: "°C") }
        if let inverterT = s["invActTemp"], !inverterT.isEmpty { d.inverterTemperatureText = displayValue(inverterT, suffix: "°C") }

        return d
    }

    static func recomputeDoorStatusText(from dashboard: VehicleDashboardState) -> String {
        let details = [
            dashboard.driverDoorStatusText,
            dashboard.passengerDoorStatusText,
            dashboard.leftRearDoorStatusText,
            dashboard.rightRearDoorStatusText
        ]
        let known = details.filter { $0 != "--" && !$0.isEmpty }
        guard !known.isEmpty else { return dashboard.doorStatusText }
        if known.contains(where: { isOpenStatusText($0) }) { return "未关" }
        if known.count == details.count && known.allSatisfy({ isClosedStatusText($0) }) { return "全关" }
        return dashboard.doorStatusText
    }

    static func recomputeWindowStatusText(from dashboard: VehicleDashboardState) -> String {
        let details = [
            dashboard.leftFrontWindowStatusText,
            dashboard.rightFrontWindowStatusText,
            dashboard.leftRearWindowStatusText,
            dashboard.rightRearWindowStatusText
        ]
        let known = details.filter { $0 != "--" && !$0.isEmpty }
        guard !known.isEmpty else { return dashboard.windowStatusText }
        if known.contains(where: { isOpenStatusText($0) }) { return "未关" }
        if known.count == details.count && known.allSatisfy({ isClosedStatusText($0) }) { return "全关" }
        return dashboard.windowStatusText
    }


}

enum VehicleStateMerger {
    static func mergeHTTPBase(current state: VehicleState, newState: VehicleState) -> VehicleState {
        var merged = newState
        // 手机侧 BLE 邻近值不是 HTTP 车况字段，始终保留本地 live overlay 基线。
        merged.bleRssi = state.bleRssi
        merged.phoneNearby = state.phoneNearby
        return merged
    }

    static func mergeHTTPBaseDashboard(current dashboard: VehicleDashboardState, newDashboard: VehicleDashboardState) -> VehicleDashboardState {
        var dash = dashboard
        dash.updatedAt = newDashboard.updatedAt
        dash.updatedAtText = newDashboard.updatedAtText

        dash.energyType = newDashboard.energyType
        dash.electricRangeKm = newDashboard.electricRangeKm
        dash.electricFullRangeKm = newDashboard.electricFullRangeKm
        dash.fuelRangeKm = newDashboard.fuelRangeKm
        dash.fuelFullRangeKm = newDashboard.fuelFullRangeKm
        dash.batteryPercentValue = newDashboard.batteryPercentValue
        dash.fuelPercentValue = newDashboard.fuelPercentValue

        dash.batteryRemainingText = newDashboard.batteryRemainingText
        dash.batteryHealthPercentText = newDashboard.batteryHealthPercentText
        dash.batteryVoltageText = newDashboard.batteryVoltageText
        dash.batteryAuxText = newDashboard.batteryAuxText

        dash.cabinTemperatureText = newDashboard.cabinTemperatureText
        dash.batteryTemperatureText = newDashboard.batteryTemperatureText
        dash.motorTemperatureText = newDashboard.motorTemperatureText
        dash.inverterTemperatureText = newDashboard.inverterTemperatureText

        // HTTP 车身：有有效文案才覆盖，避免缺字段 "--" 冲掉 MQTT 实时态
        func takeBody(_ newValue: String, current: String) -> String {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v == "--" { return current }
            return v
        }
        dash.lockStatusText = takeBody(newDashboard.lockStatusText, current: dash.lockStatusText)
        dash.doorStatusText = takeBody(newDashboard.doorStatusText, current: dash.doorStatusText)
        dash.windowStatusText = takeBody(newDashboard.windowStatusText, current: dash.windowStatusText)
        dash.tailgateStatusText = takeBody(newDashboard.tailgateStatusText, current: dash.tailgateStatusText)
        dash.driverDoorStatusText = takeBody(newDashboard.driverDoorStatusText, current: dash.driverDoorStatusText)
        dash.passengerDoorStatusText = takeBody(newDashboard.passengerDoorStatusText, current: dash.passengerDoorStatusText)
        dash.leftRearDoorStatusText = takeBody(newDashboard.leftRearDoorStatusText, current: dash.leftRearDoorStatusText)
        dash.rightRearDoorStatusText = takeBody(newDashboard.rightRearDoorStatusText, current: dash.rightRearDoorStatusText)
        dash.leftFrontWindowStatusText = takeBody(newDashboard.leftFrontWindowStatusText, current: dash.leftFrontWindowStatusText)
        dash.rightFrontWindowStatusText = takeBody(newDashboard.rightFrontWindowStatusText, current: dash.rightFrontWindowStatusText)
        dash.leftRearWindowStatusText = takeBody(newDashboard.leftRearWindowStatusText, current: dash.leftRearWindowStatusText)
        dash.rightRearWindowStatusText = takeBody(newDashboard.rightRearWindowStatusText, current: dash.rightRearWindowStatusText)

        dash.isCharging = newDashboard.isCharging
        dash.chargingPowerText = newDashboard.chargingPowerText
        dash.chargingStatusText = newDashboard.chargingStatusText
        dash.chargingPowerValueText = newDashboard.chargingPowerValueText
        dash.obcCurrentText = newDashboard.obcCurrentText
        dash.obcTemperatureText = newDashboard.obcTemperatureText
        dash.chargingStateText = newDashboard.chargingStateText

        dash.steeringAngleText = newDashboard.steeringAngleText
        dash.throttlePercentText = newDashboard.throttlePercentText
        dash.brakePercentText = newDashboard.brakePercentText
        dash.totalMileageText = newDashboard.totalMileageText
        dash.yesterdayMileageText = newDashboard.yesterdayMileageText
        dash.fuelRemainingText = newDashboard.fuelRemainingText
        dash.averageFuelConsumptionText = newDashboard.averageFuelConsumptionText
        dash.averagePowerConsumptionText = newDashboard.averagePowerConsumptionText

        dash.lowBeamText = newDashboard.lowBeamText
        dash.highBeamText = newDashboard.highBeamText
        dash.leftTurnText = newDashboard.leftTurnText
        dash.rightTurnText = newDashboard.rightTurnText
        dash.positionLightText = newDashboard.positionLightText
        dash.frontFogText = newDashboard.frontFogText
        return dash
    }

    static func mergeRealtime(current state: VehicleState, newState: VehicleState) -> VehicleState {
        var merged = state
        merged.timestamp = newState.timestamp
        merged.online = newState.online
        if newState.locked != nil { merged.locked = newState.locked }
        if newState.doorsClosed != nil { merged.doorsClosed = newState.doorsClosed }
        if newState.driverDoorOpen != nil { merged.driverDoorOpen = newState.driverDoorOpen }
        if newState.trunkOpen != nil { merged.trunkOpen = newState.trunkOpen }
        if newState.windowsClosed != nil { merged.windowsClosed = newState.windowsClosed }
        if newState.acOn != nil { merged.acOn = newState.acOn }
        if newState.acTemperature != nil { merged.acTemperature = newState.acTemperature }
        if newState.gear != .unknown { merged.gear = newState.gear }
        if newState.power != .unknown { merged.power = newState.power }
        if newState.physicalKeyPosition != .unknown { merged.physicalKeyPosition = newState.physicalKeyPosition }
        if newState.fuelLevel != nil { merged.fuelLevel = newState.fuelLevel }
        if newState.fuelRange != nil { merged.fuelRange = newState.fuelRange }
        if newState.oilRange != nil { merged.oilRange = newState.oilRange }
        if newState.speed != nil { merged.speed = newState.speed }
        return merged
    }

    static func mergeRealtimeDashboard(current dashboard: VehicleDashboardState, newDashboard: VehicleDashboardState) -> VehicleDashboardState {
        var dash = dashboard
        func takeBody(_ newValue: String, current: String) -> String {
            let v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty || v == "--" { return current }
            return v
        }
        dash.lockStatusText = takeBody(newDashboard.lockStatusText, current: dash.lockStatusText)
        dash.doorStatusText = takeBody(newDashboard.doorStatusText, current: dash.doorStatusText)
        dash.windowStatusText = takeBody(newDashboard.windowStatusText, current: dash.windowStatusText)
        dash.tailgateStatusText = takeBody(newDashboard.tailgateStatusText, current: dash.tailgateStatusText)
        dash.driverDoorStatusText = takeBody(newDashboard.driverDoorStatusText, current: dash.driverDoorStatusText)
        dash.passengerDoorStatusText = takeBody(newDashboard.passengerDoorStatusText, current: dash.passengerDoorStatusText)
        dash.leftRearDoorStatusText = takeBody(newDashboard.leftRearDoorStatusText, current: dash.leftRearDoorStatusText)
        dash.rightRearDoorStatusText = takeBody(newDashboard.rightRearDoorStatusText, current: dash.rightRearDoorStatusText)
        dash.leftFrontWindowStatusText = takeBody(newDashboard.leftFrontWindowStatusText, current: dash.leftFrontWindowStatusText)
        dash.rightFrontWindowStatusText = takeBody(newDashboard.rightFrontWindowStatusText, current: dash.rightFrontWindowStatusText)
        dash.leftRearWindowStatusText = takeBody(newDashboard.leftRearWindowStatusText, current: dash.leftRearWindowStatusText)
        dash.rightRearWindowStatusText = takeBody(newDashboard.rightRearWindowStatusText, current: dash.rightRearWindowStatusText)
        if newDashboard.tireTemperatureText != "--" { dash.tireTemperatureText = newDashboard.tireTemperatureText }
        if newDashboard.leftFrontTirePressureText != "--" { dash.leftFrontTirePressureText = newDashboard.leftFrontTirePressureText }
        if newDashboard.rightFrontTirePressureText != "--" { dash.rightFrontTirePressureText = newDashboard.rightFrontTirePressureText }
        if newDashboard.leftRearTirePressureText != "--" { dash.leftRearTirePressureText = newDashboard.leftRearTirePressureText }
        if newDashboard.rightRearTirePressureText != "--" { dash.rightRearTirePressureText = newDashboard.rightRearTirePressureText }
        if newDashboard.acTemperatureText != "--" { dash.acTemperatureText = newDashboard.acTemperatureText }
        if newDashboard.cabinTemperatureText != "--" { dash.cabinTemperatureText = newDashboard.cabinTemperatureText }
        if newDashboard.batteryPercentValue != nil { dash.batteryPercentValue = newDashboard.batteryPercentValue }
        if newDashboard.batteryRemainingText != "--" { dash.batteryRemainingText = newDashboard.batteryRemainingText }
        if newDashboard.electricRangeKm > 0 { dash.electricRangeKm = newDashboard.electricRangeKm }
        if newDashboard.fuelRangeKm > 0 { dash.fuelRangeKm = newDashboard.fuelRangeKm }
        if newDashboard.fuelPercentValue != nil { dash.fuelPercentValue = newDashboard.fuelPercentValue }
        if newDashboard.fuelRemainingText != "--" { dash.fuelRemainingText = newDashboard.fuelRemainingText }
        if newDashboard.chargingStatusText != "--" {
            dash.isCharging = (newDashboard.chargingStatusText == "是")
            dash.chargingStatusText = newDashboard.chargingStatusText
        } else if newDashboard.isCharging {
            dash.isCharging = true
            dash.chargingStatusText = "是"
        }
        if newDashboard.chargingPowerText != "--" { dash.chargingPowerText = newDashboard.chargingPowerText }
        if newDashboard.chargingPowerValueText != "--" { dash.chargingPowerValueText = newDashboard.chargingPowerValueText }
        if newDashboard.totalMileageText != "--" { dash.totalMileageText = newDashboard.totalMileageText }
        if newDashboard.yesterdayMileageText != "--" { dash.yesterdayMileageText = newDashboard.yesterdayMileageText }
        if newDashboard.averageFuelConsumptionText != "--" { dash.averageFuelConsumptionText = newDashboard.averageFuelConsumptionText }
        if newDashboard.averagePowerConsumptionText != "--" { dash.averagePowerConsumptionText = newDashboard.averagePowerConsumptionText }
        if newDashboard.speedText != "--" { dash.speedText = newDashboard.speedText }
        if newDashboard.averageSpeedText != "--" { dash.averageSpeedText = newDashboard.averageSpeedText }
        if newDashboard.lowBeamText != "--" { dash.lowBeamText = newDashboard.lowBeamText }
        if newDashboard.highBeamText != "--" { dash.highBeamText = newDashboard.highBeamText }
        if newDashboard.leftTurnText != "--" { dash.leftTurnText = newDashboard.leftTurnText }
        if newDashboard.rightTurnText != "--" { dash.rightTurnText = newDashboard.rightTurnText }
        if newDashboard.positionLightText != "--" { dash.positionLightText = newDashboard.positionLightText }
        if newDashboard.frontFogText != "--" { dash.frontFogText = newDashboard.frontFogText }
        dash.updatedAt = newDashboard.updatedAt
        dash.updatedAtText = newDashboard.updatedAtText
        return dash
    }
}

enum VehicleHTTPMetaMapper {
    static func coordinate(from carStatus: [String: String]) -> VehicleCoordinateUpdate? {
        guard let lat = parseDouble(carStatus["latitude"]),
              let lng = parseDouble(carStatus["longitude"]),
              lat != 0,
              lng != 0 else {
            return nil
        }
        let gcj = LocationResolver.wgs84ToGcj02(lat: lat, lng: lng)
        let addressHint = carStatus["address"]
        return VehicleCoordinateUpdate(latGcj: gcj.lat, lngGcj: gcj.lng, addressHint: addressHint)
    }

    static func dashboard(base dashboard: VehicleDashboardState, carInfo: [String: String]) -> VehicleDashboardState {
        var dash = dashboard
        let model = carInfo["carName"]
            ?? carInfo["carModelName"]
            ?? carInfo["carSeriesName"]
            ?? carInfo["carTypeName"]
            ?? carInfo["model"]
            ?? ""
        if !model.isEmpty { dash.vehicleName = model }
        let imageURL = carInfo["image"] ?? carInfo["imageUrl"] ?? ""
        if !imageURL.isEmpty { dash.vehicleImageURL = imageURL }
        dash.vinText = carInfo["vin"] ?? dash.vinText
        dash.userIdText = carInfo["bindCarUserMobile"] ?? carInfo["userId"] ?? dash.userIdText
        return dash
    }

    static func profile(carInfo: [String: String], carStatus: [String: String]) -> VehicleProfile {
        var profile = VehicleProfile()
        profile.vin = carInfo["vin"] ?? ""
        profile.modelName = carInfo["model"] ?? carInfo["carName"] ?? ""
        profile.carTypeName = carInfo["carTypeName"] ?? carInfo["carSeriesName"] ?? ""
        profile.powerType = carInfo["powerType"] ?? carStatus["powerType"] ?? ""
        profile.engineType = carInfo["engineType"] ?? carInfo["physicsEngine"] ?? ""
        profile.vehicleType = carInfo["carTypeName"] ?? carInfo["carName"] ?? ""
        profile.driveType = carStatus["driveType"] ?? ""
        profile.fuelType = carStatus["fuelType"] ?? ""
        profile.capabilities.hasFuel = nil
        profile.capabilities.supportHybridMileage = carInfo["supportHybridMileage"] == "1"
        profile.capabilities.supportBatteryIndicate = carInfo["supportBatteryIndicate"] == "1"
        profile.capabilities.supportChargePower = carInfo["supportChargePower"] == "1"
        return profile
    }

    static func supportsMQTT(carInfo: [String: String]) -> Bool {
        carInfo["supportMqtt"] == "1"
    }
}
