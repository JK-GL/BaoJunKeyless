import Foundation

/// 空调设定温度草稿（官方风格）：
/// - 关着时滑动只记本地，不发网络
/// - 车况 `accCntTemp` 仍是权威回落
/// - 按 VIN 跨会话保留用户刚调过的目标温度
enum ACTemperatureDraftStore {
    private static let defaults = UserDefaults.standard
    private static let validRange: ClosedRange<Int> = 17...33

    static func load(vin: String) -> Double? {
        let key = storageKey(vin: vin)
        guard !key.isEmpty else { return nil }
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.integer(forKey: key)
        guard validRange.contains(value) else { return nil }
        return Double(value)
    }

    static func save(vin: String, temperature: Double) {
        let key = storageKey(vin: vin)
        guard !key.isEmpty else { return }
        let clamped = Int(max(Double(validRange.lowerBound), min(Double(validRange.upperBound), temperature.rounded())))
        defaults.set(clamped, forKey: key)
    }

    static func clear(vin: String) {
        let key = storageKey(vin: vin)
        guard !key.isEmpty else { return }
        defaults.removeObject(forKey: key)
    }

    /// 打开空调面板时的温度优先级：本地草稿 > 车况 accCntTemp > 默认。
    static func resolvedTemperature(
        vin: String,
        vehicleTemperature: Double?,
        defaultTemperature: Double = 22
    ) -> Double {
        if let draft = load(vin: vin) {
            return draft
        }
        if let vehicleTemperature {
            return max(17, min(33, vehicleTemperature))
        }
        return max(17, min(33, defaultTemperature))
    }

    private static func storageKey(vin: String) -> String {
        let trimmed = vin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return AppDefaultsKey.ClimateDraft.temperatureByVINPrefix + trimmed
    }
}
