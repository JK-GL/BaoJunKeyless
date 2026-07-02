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

        if let locked = parseLocked(s["doorLockStatus"]) { next.locked = locked }
        if let doorsClosed = parseDoorClosed(s) { next.doorsClosed = doorsClosed }
        if let driverOpen = parseOpen(s["door1OpenStatus"]) { next.driverDoorOpen = driverOpen }
        if let trunkOpen = parseOpen(s["tailDoorOpenStatus"]) { next.trunkOpen = trunkOpen }
        if let windowsClosed = parseWindowsClosed(s) { next.windowsClosed = windowsClosed }

        if let batterySoc = parseDouble(s["batterySoc"]) { next.fuelLevel = batterySoc }
        if let leftMileage = parseDouble(s["leftMileage"]) { next.fuelRange = leftMileage }
        if let leftFuel = parseDouble(s["leftFuel"]) {
            next.oilRange = parseDouble(s["oilLeftMileage"]) ?? next.oilRange
            next.fuelLevel = next.fuelLevel ?? leftFuel
        }
        if let oilMileage = parseDouble(s["oilLeftMileage"]) { next.oilRange = oilMileage }

        if let ac = parseACStatus(s["acStatus"]) { next.acOn = ac }
        if let temp = parseDouble(s["accCntTemp"] ?? s["interiorTemperature"]) { next.acTemperature = temp }
        if let gear = parseGear(s["autoGearStatus"]) { next.gear = gear }
        if let speed = parseDouble(s["speed"] ?? s["vehSpd"] ?? s["vehSpdAvgDrvn"]) { next.speed = speed }
        let physicalKeyPosition = parsePhysicalKeyPosition(s["keyStatus"])
        next.physicalKeyPosition = physicalKeyPosition
        next.phoneNearby = (physicalKeyPosition != .farAway && physicalKeyPosition != .unknown)
        if let rssi = parseInt(s["bleRssi"]) { next.bleRssi = rssi }
        if let power = parsePowerState(s) { next.power = power }
        return next
    }

    static func httpDashboard(from s: [String: String], base dashboard: VehicleDashboardState) -> VehicleDashboardState {
        var d = dashboard
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

        d.batteryRemainingText = displayBatteryRemaining(s, fallback: dashboard.batteryRemainingText)
        d.batteryHealthPercentText = displayBatteryHealth(s, fallback: dashboard.batteryHealthPercentText)
        d.batteryVoltageText = displayValue(s["voltage"], suffix: "V")
        d.batteryAuxText = displayValue(s["lowBatVol"], suffix: "V")

        d.cabinTemperatureText = displayValue(s["interiorTemperature"], suffix: "°C")
        d.acTemperatureText = displayACTemperature(s, fallback: dashboard.acTemperatureText)
        d.batteryTemperatureText = displayValue(s["batAvgTemp"] ?? s["batMinTemp"], suffix: "°C")
        d.motorTemperatureText = displayValue(s["tmActTemp"], suffix: "°C")
        d.inverterTemperatureText = displayValue(s["invActTemp"], suffix: "°C")

        let charging = s["charging"] == "1"
        d.isCharging = charging
        d.chargingStatusText = charging ? "是" : "否"
        d.chargingPowerText = displayValue(s["chargePower"], suffix: " kW")
        d.chargingPowerValueText = displayValue(s["chargePower"], suffix: " kW")
        d.obcCurrentText = displayValue(s["obcOtpCur"], suffix: "A")
        d.obcTemperatureText = displayValue(s["obcTemp"], suffix: "°C")
        d.chargingStateText = displayText(s["rechargeStatus"]) ?? displayText(s["vecChrgingSts"]) ?? "--"

        d.lockStatusText = (parseLocked(s["doorLockStatus"]) == true) ? "已锁车" : ((parseLocked(s["doorLockStatus"]) == false) ? "未锁" : "--")
        d.doorStatusText = (parseDoorClosed(s) == true) ? "全关" : ((parseDoorClosed(s) == false) ? "未关" : "--")
        d.windowStatusText = (parseWindowsClosed(s) == true) ? "全关" : ((parseWindowsClosed(s) == false) ? "未关" : "--")
        d.tailgateStatusText = displayOpenStatus(s["tailDoorOpenStatus"], closedText: "已锁", openText: "已开")
        d.driverDoorStatusText = displayOpenStatus(s["door1OpenStatus"], closedText: "已关", openText: "未关")
        d.passengerDoorStatusText = displayOpenStatus(s["door2OpenStatus"], closedText: "已关", openText: "未关")
        d.leftRearDoorStatusText = displayOpenStatus(s["door3OpenStatus"], closedText: "已关", openText: "未关")
        d.rightRearDoorStatusText = displayOpenStatus(s["door4OpenStatus"], closedText: "已关", openText: "未关")
        d.leftFrontWindowStatusText = displayOpenStatus(s["window1Status"], closedText: "已关", openText: "已开")
        d.rightFrontWindowStatusText = displayOpenStatus(s["window2Status"], closedText: "已关", openText: "已开")
        d.leftRearWindowStatusText = displayOpenStatus(s["window3Status"], closedText: "已关", openText: "已开")
        d.rightRearWindowStatusText = displayOpenStatus(s["window4Status"], closedText: "已关", openText: "已开")

        d.speedText = displayValue(s["speed"] ?? s["vehSpd"] ?? s["vehSpdAvgDrvn"], suffix: "km/h")
        d.averageSpeedText = displayValue(s["vehSpdAvgDrvn"], suffix: "km/h")
        d.steeringAngleText = displayValue(s["strWhAng"], suffix: "°")
        d.throttlePercentText = displayValue(s["accActPos"], suffix: "%")
        d.brakePercentText = displayValue(s["brakPedalPos"], suffix: "%")
        d.totalMileageText = displayValue(s["mileage"], suffix: "km")
        d.yesterdayMileageText = displayValue(s["yesterMileage"], suffix: "km")
        d.fuelRemainingText = displayFuelRemaining(s, fallback: dashboard.fuelRemainingText)
        d.averageFuelConsumptionText = displayValue(s["avgFuel"], suffix: "L/100km")
        d.averagePowerConsumptionText = displayPowerConsumption(s, fallback: dashboard.averagePowerConsumptionText)

        d.lowBeamText = displayBool(s["dipHeadLight"])
        d.highBeamText = displayBool(s["lowBeamLight"])
        d.leftTurnText = displayBool(s["leftTurnLight"])
        d.rightTurnText = displayBool(s["rightTurnLight"])
        d.positionLightText = displayBool(s["positionLight"])
        d.frontFogText = displayBool(s["frontFogLight"])
        return d
    }

    static func mqttState(from s: [String: String], base state: VehicleState) -> VehicleState {
        var next = state
        next.timestamp = parseTimestamp(s["collectTime"]) ?? Date()
        next.online = true
        if let locked = parseLocked(s["doorLockStatus"]) { next.locked = locked }
        if let doorsClosed = parseDoorClosed(s) { next.doorsClosed = doorsClosed }
        if let driverOpen = parseOpen(s["door1OpenStatus"]) { next.driverDoorOpen = driverOpen }
        if let trunkOpen = parseOpen(s["tailDoorOpenStatus"]) { next.trunkOpen = trunkOpen }
        if let windowsClosed = parseWindowsClosed(s) { next.windowsClosed = windowsClosed }
        if let ac = parseACStatus(s["acStatus"]) { next.acOn = ac }
        if let speed = parseDouble(s["speed"] ?? s["vehSpd"] ?? s["vehSpdAvgDrvn"]) { next.speed = speed }
        return next
    }

    static func mqttDashboard(from s: [String: String], base dashboard: VehicleDashboardState) -> VehicleDashboardState {
        var d = dashboard
        if let locked = parseLocked(s["doorLockStatus"]) { d.lockStatusText = locked ? "已锁车" : "未锁" }
        if let doorsClosed = parseDoorClosed(s) { d.doorStatusText = doorsClosed ? "全关" : "未关" }
        if let windowsClosed = parseWindowsClosed(s) { d.windowStatusText = windowsClosed ? "全关" : "未关" }
        if s["tailDoorOpenStatus"] != nil { d.tailgateStatusText = displayOpenStatus(s["tailDoorOpenStatus"], closedText: "已锁", openText: "已开") }
        if s["door1OpenStatus"] != nil { d.driverDoorStatusText = displayOpenStatus(s["door1OpenStatus"], closedText: "已关", openText: "未关") }
        if s["door2OpenStatus"] != nil { d.passengerDoorStatusText = displayOpenStatus(s["door2OpenStatus"], closedText: "已关", openText: "未关") }
        if s["door3OpenStatus"] != nil { d.leftRearDoorStatusText = displayOpenStatus(s["door3OpenStatus"], closedText: "已关", openText: "未关") }
        if s["door4OpenStatus"] != nil { d.rightRearDoorStatusText = displayOpenStatus(s["door4OpenStatus"], closedText: "已关", openText: "未关") }
        if s["window1Status"] != nil { d.leftFrontWindowStatusText = displayOpenStatus(s["window1Status"], closedText: "已关", openText: "已开") }
        if s["window2Status"] != nil { d.rightFrontWindowStatusText = displayOpenStatus(s["window2Status"], closedText: "已关", openText: "已开") }
        if s["window3Status"] != nil { d.leftRearWindowStatusText = displayOpenStatus(s["window3Status"], closedText: "已关", openText: "已开") }
        if s["window4Status"] != nil { d.rightRearWindowStatusText = displayOpenStatus(s["window4Status"], closedText: "已关", openText: "已开") }
        if let ac = parseACStatus(s["acStatus"]) { d.acTemperatureText = ac ? "开启" : "关闭" }
        if let speed = s["speed"] ?? s["vehSpd"], !speed.isEmpty { d.speedText = "\(speed)km/h" }
        if let averageSpeed = s["vehSpdAvgDrvn"], !averageSpeed.isEmpty { d.averageSpeedText = "\(averageSpeed)km/h" }
        d.updatedAt = parseTimestamp(s["collectTime"]) ?? Date()
        d.updatedAtText = formatTime(d.updatedAt)
        return d
    }
}

enum VehicleStateMerger {
    static func mergeHTTPBase(current state: VehicleState, newState: VehicleState) -> VehicleState {
        var merged = state
        merged.timestamp = newState.timestamp
        merged.online = newState.online
        merged.gear = newState.gear
        merged.power = newState.power
        merged.speed = newState.speed
        merged.physicalKeyPosition = newState.physicalKeyPosition
        merged.phoneNearby = newState.phoneNearby
        merged.fuelLevel = newState.fuelLevel
        merged.fuelRange = newState.fuelRange
        merged.oilRange = newState.oilRange
        if merged.locked == nil { merged.locked = newState.locked }
        if merged.doorsClosed == nil { merged.doorsClosed = newState.doorsClosed }
        if merged.driverDoorOpen == nil { merged.driverDoorOpen = newState.driverDoorOpen }
        if merged.trunkOpen == nil { merged.trunkOpen = newState.trunkOpen }
        if merged.windowsClosed == nil { merged.windowsClosed = newState.windowsClosed }
        if merged.acOn == nil { merged.acOn = newState.acOn }
        if merged.acTemperature == nil { merged.acTemperature = newState.acTemperature }
        return merged
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
        return merged
    }

    static func mergeRealtimeDashboard(current dashboard: VehicleDashboardState, newDashboard: VehicleDashboardState) -> VehicleDashboardState {
        var dash = dashboard
        dash.lockStatusText = newDashboard.lockStatusText
        dash.doorStatusText = newDashboard.doorStatusText
        dash.windowStatusText = newDashboard.windowStatusText
        dash.tailgateStatusText = newDashboard.tailgateStatusText
        dash.driverDoorStatusText = newDashboard.driverDoorStatusText
        dash.passengerDoorStatusText = newDashboard.passengerDoorStatusText
        dash.leftRearDoorStatusText = newDashboard.leftRearDoorStatusText
        dash.rightRearDoorStatusText = newDashboard.rightRearDoorStatusText
        dash.leftFrontWindowStatusText = newDashboard.leftFrontWindowStatusText
        dash.rightFrontWindowStatusText = newDashboard.rightFrontWindowStatusText
        dash.leftRearWindowStatusText = newDashboard.leftRearWindowStatusText
        dash.rightRearWindowStatusText = newDashboard.rightRearWindowStatusText
        dash.acTemperatureText = newDashboard.acTemperatureText
        dash.speedText = newDashboard.speedText
        dash.averageSpeedText = newDashboard.averageSpeedText
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
