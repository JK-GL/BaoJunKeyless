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
    guard let raw else { return nil }
    if raw == "0" { return true }
    if raw == "1" { return false }
    return nil
}

func parseOpen(_ raw: String?) -> Bool? {
    guard let raw else { return nil }
    if raw == "0" { return false }
    if raw == "1" { return true }
    return nil
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
    guard !parsed.isEmpty else { return nil }
    return !parsed.contains(true)
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
    if let engine = s["engineStatus"] {
        if engine == "1" { return .ready }
        if engine == "0" { return .off }
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