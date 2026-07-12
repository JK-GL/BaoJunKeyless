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
    if let ms = Double(raw), ms > 1000000000000 { return Date(timeIntervalSince1970: ms / 1000) }
    if let sec = Double(raw), sec > 1000000000 { return Date(timeIntervalSince1970: sec) }
    return AppDateFormatters.timestampMillis.date(from: raw)
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
    if let total = parseOpen(s["doorOpenStatus"]) { return !total }
    let values = [s["door1OpenStatus"], s["door2OpenStatus"], s["door3OpenStatus"], s["door4OpenStatus"]]
    let parsed = values.compactMap(parseOpen)
    guard !parsed.isEmpty else { return nil }
    return !parsed.contains(true)
}

func parseWindowsClosed(_ s: [String: String]) -> Bool? {
    if let total = parseOpen(s["windowStatus"]) { return !total }
    let values = [s["window1Status"], s["window2Status"], s["window3Status"], s["window4Status"]]
    let parsed = values.compactMap(parseOpen)
    // 开度 > 0 也视为开
    let degrees = [s["window1OpenDegree"], s["window2OpenDegree"], s["window3OpenDegree"], s["window4OpenDegree"]]
    let degreeOpen = degrees.compactMap { parseDouble($0) }.contains { $0 > 0 }
    if parsed.isEmpty && !degreeOpen {
        // half-open flags
        let half = [s["window1HalfOpenStatus"], s["window2HalfOpenStatus"], s["window3HalfOpenStatus"], s["window4HalfOpenStatus"], s["windowHalfOpenStatus"]]
        let halfOpen = half.compactMap(parseOpen).contains(true)
        return halfOpen ? false : nil
    }
    if degreeOpen { return false }
    if parsed.contains(true) { return false }
    if !parsed.isEmpty { return true }
    return nil
}

func displayWindowStatus(_ status: String?, degree: String?, half: String? = nil, closedText: String = "已关", openText: String = "已开") -> String {
    if let open = parseOpen(status) {
        return open ? openText : closedText
    }
    if let halfOpen = parseOpen(half), halfOpen {
        return openText
    }
    if let deg = parseDouble(degree), deg > 0 {
        return openText
    }
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
    switch raw {
    case "0": return false
    case "1", "2": return true
    default: return nil
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
            return ["rfTirPrVal", "fr"]
        case .leftRear:
            return ["lrTirPrVal", "rl"]
        case .rightRear:
            return ["rrTirPrVal", "rr"]
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
    if let fallbackCarStatus, let tireTemp = fallbackCarStatus["tirTemp"], !tireTemp.isEmpty {
        return displayValue(tireTemp, suffix: "°C")
    }
    return "--"
}

func parseGear(_ raw: String?) -> VehicleGear? {
    guard let raw else { return nil }
    switch raw {
    case "10": return .p
    case "14": return .r
    case "13": return .n
    case "12": return .d
    default: return .unknown
    }
}

func parsePowerState(_ s: [String: String]) -> VehiclePowerState? {
    // 主字段：engineStatus 0=关 1=开（MQTT_FIELDS / status_source_map）
    let candidates = [
        s["engineStatus"],
        s["powerStatus"],
        s["vehPowerMode"],
        s["vehiclePowerStatus"],
        s["sysPowerMode"],
        s["ignitionStatus"],
        s["accStatus"]
    ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

    for raw in candidates {
        switch raw {
        case "0", "off", "OFF", "false", "FALSE":
            return .off
        case "1", "2", "on", "ON", "ready", "READY", "true", "TRUE":
            // 1 常表示运行/就绪；细分不足时按 ready，避免误当 unknown 卡无感
            return .ready
        case "3", "acc", "ACC":
            return .acc
        default:
            if let value = Int(raw) {
                if value == 0 { return .off }
                if value > 0 { return .ready }
            }
            continue
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
    if let temp = s["interiorTemperature"], !temp.isEmpty { return "\(temp)°C" }
    if let ac = parseACStatus(s["acStatus"]) { return ac ? "开启" : "关闭" }
    return fallback
}