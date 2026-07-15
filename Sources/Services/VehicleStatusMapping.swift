import Foundation

// MARK: - 纯数据解析工具（无实例依赖，仅操作传参）

func displayBool(_ raw: String?) -> String {
    guard let raw else { return "--" }
    return raw == "1" ? "开启" : (raw == "0" ? "关闭" : raw)
}

func displayValue(_ raw: String?, suffix: String = "") -> String {
    guard let raw, !raw.isEmpty else { return "--" }
    return raw + suffix
}

func displayText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    return raw
}

func maskHex(_ raw: String?, visiblePrefix: Int, visibleSuffix: Int) -> String {
    guard let raw, !raw.isEmpty else { return "--" }
    guard raw.count > visiblePrefix + visibleSuffix else { return raw }
    let prefix = raw.prefix(visiblePrefix)
    let suffix = raw.suffix(visibleSuffix)
    return "\(prefix)...\(suffix)"
}

func parseInt(_ raw: String?) -> Int? {
    guard let raw, !raw.isEmpty else { return nil }
    return Int(Double(raw) ?? .nan)
}

func parseDouble(_ raw: String?) -> Double? {
    guard let raw, !raw.isEmpty else { return nil }
    return Double(raw)
}

func parseTimestamp(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // 1) epoch millis / seconds
    if let ms = Double(text), ms > 1000000000000 { return Date(timeIntervalSince1970: ms / 1000) }
    if let sec = Double(text), sec > 1000000000 { return Date(timeIntervalSince1970: sec) }
    // 2) official HTTP/MQTT string formats
    //    "yyyy-MM-dd HH:mm:ss.SSS" / "yyyy-MM-dd HH:mm:ss"
    if let d = AppDateFormatters.timestampMillis.date(from: text) { return d }
    if let d = AppDateFormatters.fullDateTime.date(from: text) { return d }
    // 3) sometimes trailing Z / timezone-less variants
    let trimmed = text
        .replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")
    if let d = AppDateFormatters.timestampMillis.date(from: trimmed) { return d }
    if let d = AppDateFormatters.fullDateTime.date(from: trimmed) { return d }
    return nil
}

func formatTime(_ date: Date) -> String {
    AppDateFormatters.vehicleTime.string(from: date)
}

func formatDateTime(_ date: Date) -> String {
    AppDateFormatters.fullDateTime.string(from: date)
}

func parseLocked(_ raw: String?) -> Bool? {
    // doorLockStatus: 0=锁 1=解锁；兼容 true/false/bool 字符串
    guard let normalized = normalizeBinaryStatus(raw) else { return nil }
    switch normalized {
    case "0", "false", "off", "lock", "locked":
        return true
    case "1", "true", "on", "unlock", "unlocked":
        return false
    default:
        return nil
    }
}

func parseOpen(_ raw: String?) -> Bool? {
    // openStatus: 0=关 1=开
    guard let normalized = normalizeBinaryStatus(raw) else { return nil }
    switch normalized {
    case "0", "false", "off", "close", "closed":
        return false
    case "1", "true", "on", "open", "opened":
        return true
    default:
        return nil
    }
}

/// 兼容 "0"/"1"/0/1/true/false/"true"/"false" 以及 "未关·缓存" 之类脏值前缀
func normalizeBinaryStatus(_ raw: String?) -> String? {
    guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
    if let cacheRange = text.range(of: "·缓存") {
        text = String(text[..<cacheRange.lowerBound])
    }
    text = text.lowercased()
    if text == "已关" || text == "全关" || text == "已锁" || text == "已锁车" { return "0" }
    if text == "未关" || text == "已开" || text == "打开" || text == "未锁" { return "1" }
    return text
}

func parseDoorClosed(_ s: [String: String]) -> Bool? {
    // 任一明细开即可判未关；只有四门明细齐全且都关，才能由明细判全关。
    let values = [s["door1OpenStatus"], s["door2OpenStatus"], s["door3OpenStatus"], s["door4OpenStatus"]]
    let parsed = values.map(parseOpen)
    if parsed.contains(where: { $0 == true }) { return false }
    if parsed.allSatisfy({ $0 == false }) { return true }
    if let total = parseOpen(s["doorOpenStatus"]) { return !total }
    return nil
}

func parseWindowsClosed(_ s: [String: String]) -> Bool? {
    let values = [s["window1Status"], s["window2Status"], s["window3Status"], s["window4Status"]]
    let parsed = values.map(parseOpen)
    let degrees = [s["window1OpenDegree"], s["window2OpenDegree"], s["window3OpenDegree"], s["window4OpenDegree"]]
    let parsedDegrees = degrees.map(parseDouble)
    let half = [s["window1HalfOpenStatus"], s["window2HalfOpenStatus"], s["window3HalfOpenStatus"], s["window4HalfOpenStatus"], s["windowHalfOpenStatus"]]
    let parsedHalf = half.map(parseOpen)

    if parsed.contains(where: { $0 == true })
        || parsedDegrees.contains(where: { ($0 ?? 0) > 0 })
        || parsedHalf.contains(where: { $0 == true }) {
        return false
    }
    // 四窗二值状态齐全，或四窗开度齐全且均为 0，才能由明细判全关。
    if parsed.allSatisfy({ $0 == false }) { return true }
    if parsedDegrees.allSatisfy({ value in value.map { $0 <= 0 } == true }) { return true }
    if let total = parseOpen(s["windowStatus"]) { return !total }
    return nil
}

func displayWindowStatus(_ status: String?, degree: String?, half: String? = nil, closedText: String = "已关", openText: String = "已开") -> String {
    // 开度/半开比二值 status 更具体；即使 status=0，只要开度>0 也必须显示已开。
    if let deg = parseDouble(degree), deg > 0 { return openText }
    if let halfOpen = parseOpen(half), halfOpen { return openText }
    if let open = parseOpen(status) { return open ? openText : closedText }
    return "--"
}

func bodyFieldsSummary(_ s: [String: String]) -> String {
    let keys = [
        "doorLockStatus", "doorOpenStatus",
        "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus", "tailDoorOpenStatus",
        "windowStatus", "window1Status", "window2Status", "window3Status", "window4Status",
        "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree"
    ]
    return keys.compactMap { key in
        guard let value = s[key], !value.isEmpty else { return nil }
        return "\(key)=\(value)"
    }.joined(separator: " ")
}

func isOpenStatusText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: "·缓存", with: "")
    return ["未关", "已开", "打开", "未锁"].contains(t)
}

func isClosedStatusText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: "·缓存", with: "")
    return ["已关", "全关", "已锁", "已锁车"].contains(t)
}

func parseACStatus(_ raw: String?) -> Bool? {
    guard let raw else { return nil }
    // 文档: 0关 1制冷 2制热 6开 7关；兼容 true/false
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "0", "7", "false", "FALSE", "off", "OFF":
        return false
    case "1", "2", "6", "true", "TRUE", "on", "ON":
        return true
    default:
        if let v = Int(raw) {
            if v == 0 || v == 7 { return false }
            if v > 0 { return true }
        }
        return nil
    }
}

func displayOpenStatus(_ raw: String?, closedText: String = "已关", openText: String = "已开") -> String {
    guard let open = parseOpen(raw) else { return "--" }
    return open ? openText : closedText
}

func displayTirePressure(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "--" }
    if raw.rangeOfCharacter(from: CharacterSet.letters) != nil { return raw }
    guard let value = Double(raw) else { return raw }
    if value > 10 { return String(Int(round(value))) }
    return String(Int(round(value * 100)))
}

func firstDisplayTirePressure(_ s: [String: String], keys: [String]) -> String {
    for key in keys {
        let text = displayTirePressure(s[key])
        if text != "--" { return text }
    }
    return "--"
}

enum TireCorner {
    case leftFront
    case rightFront
    case leftRear
    case rightRear

    var carStatusKeys: [String] {
        switch self {
        case .leftFront:
            return ["leftFrontTirePressure", "frontLeftTirePressure", "lfTirePressure", "flTirePressure", "tirePressureLF", "tirePressureFL", "tyrePressureLF", "tyrePressureFL", "tirePressure1"]
        case .rightFront:
            return ["rightFrontTirePressure", "frontRightTirePressure", "rfTirePressure", "frTirePressure", "tirePressureRF", "tirePressureFR", "tyrePressureRF", "tyrePressureFR", "tirePressure2"]
        case .leftRear:
            return ["leftRearTirePressure", "rearLeftTirePressure", "lrTirePressure", "rlTirePressure", "tirePressureLR", "tirePressureRL", "tyrePressureLR", "tyrePressureRL", "tirePressure3"]
        case .rightRear:
            return ["rightRearTirePressure", "rearRightTirePressure", "rrTirePressure", "tirePressureRR", "tyrePressureRR", "tirePressure4"]
        }
    }

    var tirePayloadKeys: [String] {
        switch self {
        case .leftFront:
            return ["lfTirPrsVal", "fl"]
        case .rightFront:
            return ["rfTirPrsVal", "rfTirPrVal", "fr"]
        case .leftRear:
            return ["lrTirPrsVal", "lrTirPrVal", "rl"]
        case .rightRear:
            return ["rrTirPrsVal", "rrTirPrVal", "rr"]
        }
    }
}

func firstDisplayTirePressure(_ s: [String: String], corner: TireCorner, preferTirePayload: Bool = false) -> String {
    let keys = preferTirePayload ? (corner.tirePayloadKeys + corner.carStatusKeys) : corner.carStatusKeys
    return firstDisplayTirePressure(s, keys: keys)
}

func displayTireTemperature(_ tirePressure: [String: String], fallbackCarStatus: [String: String]? = nil) -> String {
    if let tireTemp = tirePressure["tirTemp"], !tireTemp.isEmpty {
        return displayValue(tireTemp, suffix: "°C")
    }
    let cornerKeys = ["lfTirTempVal", "rfTirTempVal", "lrTirTempVal", "rrTirTempVal"]
    let values = cornerKeys.compactMap { parseDouble(tirePressure[$0]) }
    if !values.isEmpty {
        let average = values.reduce(0, +) / Double(values.count)
        return "\(Int(round(average)))°C"
    }
    if let fallbackCarStatus, let tireTemp = fallbackCarStatus["tirTemp"], !tireTemp.isEmpty {
        return displayValue(tireTemp, suffix: "°C")
    }
    return "--"
}

func parseGear(_ raw: String?) -> VehicleGear? {
    guard let raw else { return nil }
    // 兼容两套：E300 常见 10/14/13/12，部分文档/车型 10/20/30/40
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "10", "P", "p":
        return .p
    case "14", "20", "R", "r":
        return .r
    case "13", "30", "N", "n":
        return .n
    case "12", "40", "D", "d":
        return .d
    default:
        return .unknown
    }
}

func parsePowerState(_ s: [String: String]) -> VehiclePowerState? {
    // 上电/电源主字段（Wuling/官方对齐）：
    // - engineStatus: 0关 1开（最常见）
    // - powerStatus/vehPowerMode/...: 兼容电源模式
    // 优先 engineStatus，避免被无关 acc 字段误伤
    let orderedKeys = [
        "engineStatus",
        "powerStatus",
        "vehPowerMode",
        "vehiclePowerStatus",
        "sysPowerMode",
        "ignitionStatus"
    ]
    for key in orderedKeys {
        guard let raw = s[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
        switch raw {
        case "0", "off", "OFF", "false", "FALSE":
            return .off
        case "3", "acc", "ACC":
            return .acc
        case "1", "on", "ON", "true", "TRUE":
            // engineStatus=1 更接近已上电/运行；UI 显示“已上电”
            return key == "engineStatus" ? .on : .ready
        case "2", "ready", "READY":
            return .ready
        default:
            if let value = Int(raw) {
                if value == 0 { return .off }
                if value == 3 { return .acc }
                if value == 1 { return key == "engineStatus" ? .on : .ready }
                if value >= 2 { return .ready }
            }
            continue
        }
    }
    // accStatus 单独看：仅在没有更明确电源字段时作为弱信号
    if let acc = s["accStatus"]?.trimmingCharacters(in: .whitespacesAndNewlines), !acc.isEmpty {
        switch acc {
        case "0", "off", "OFF": return .off
        case "1", "on", "ON", "acc", "ACC": return .acc
        default: break
        }
    }
    return nil
}

func parsePhysicalKeyPosition(_ raw: String?) -> PhysicalKeyPosition {
    guard let raw else { return .unknown }
    switch raw {
    case "0": return .farAway
    case "1": return .outside
    case "2": return .inside
    default: return .unknown
    }
}

func displayBatteryRemaining(_ s: [String: String], fallback: String) -> String {
    if let kwh = s["leftBatteryPower"] ?? s["leftBatteryPowerDisplay"], !kwh.isEmpty { return "\(kwh)kWh" }
    if let soc = s["batterySoc"], !soc.isEmpty { return "\(soc)%" }
    return fallback
}

func displayBatteryHealth(_ s: [String: String], fallback: String) -> String {
    if let soh = s["batSOH"] ?? s["batHealth"], !soh.isEmpty { return "\(soh)%" }
    return fallback
}

func displayFuelRemaining(_ s: [String: String], fallback: String) -> String {
    if let percent = s["fuelPercent"] ?? s["oilPercent"] ?? s["leftFuel"], !percent.isEmpty { return "\(percent)%" }
    return fallback
}

func displayPowerConsumption(_ s: [String: String], fallback: String) -> String {
    if let avgElectronFuel = s["avgElectronFuel"], !avgElectronFuel.isEmpty { return "\(avgElectronFuel)kWh/100km" }
    if let avgElecFuel = s["avgElecFuel"], !avgElecFuel.isEmpty { return "\(avgElecFuel)kWh/100km" }
    if let avgPower = s["avgPowerConsumption"], !avgPower.isEmpty { return "\(avgPower)kWh/100km" }
    return fallback
}

func displayACTemperature(_ s: [String: String], fallback: String) -> String {
    if let temp = s["accCntTemp"], !temp.isEmpty { return "\(temp)°C" }
    if let ac = parseACStatus(s["acStatus"]) { return ac ? "开启" : "关闭" }
    return fallback
}

func parseCharging(_ s: [String: String]) -> Bool? {
    if let charging = parseOpen(s["charging"]) { return charging }
    if let indicator = parseOpen(s["vecChrgStsIndOn"]) { return indicator }
    if let raw = s["vecChrgingSts"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
       let value = Int(raw) {
        return value > 0
    }
    return nil
}

func displayChargingState(_ s: [String: String], isCharging: Bool?) -> String {
    if isCharging == true { return "充电中" }
    if parseOpen(s["wireConnect"]) == true { return "已插枪，未充电" }
    if let raw = displayText(s["rechargeStatus"]), Int(raw) == nil { return raw }
    if let raw = displayText(s["vecChrgingSts"]), Int(raw) == nil { return raw }
    if isCharging == false { return "未充电" }
    return "--"
}