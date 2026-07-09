import Foundation

/// 缓存最近一次 ble/key/query 返回的 BLE 钥匙材料，支持离线 BLE。
/// 官方 App 可以离线用蓝牙的原因就是本地缓存了这份材料。
enum VehicleBLEKeyCacheStore {
    private static let cacheKey = "VehicleBLE.KeyCache"
    private static let timestampKey = "VehicleBLE.KeyCache.Timestamp"
    private static let macKey = "VehicleBLE.KeyCache.Mac"

    /// 默认最长保留 7 天；过期后 load 返回 nil，避免旧 key 长期误用。
    static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60

    static func save(_ info: [String: String]) {
        let filtered = info.filter { !$0.value.isEmpty }
        guard let data = try? JSONSerialization.data(withJSONObject: filtered, options: []) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
        if let mac = filtered["bleMac"] ?? filtered["macAddress"], !mac.isEmpty {
            UserDefaults.standard.set(mac, forKey: macKey)
        }
    }

    /// 读取缓存；超过 maxAge 则自动清理并返回 nil。
    static func load(maxAge: TimeInterval = defaultMaxAge) -> [String: String]? {
        if let age = ageSeconds, age > maxAge {
            clear()
            return nil
        }
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            clear()
            return nil
        }
        let filtered = dict.filter { !$0.value.isEmpty }
        if filtered.isEmpty {
            clear()
            return nil
        }
        return filtered
    }

    static var cachedMac: String? {
        UserDefaults.standard.string(forKey: macKey)
    }

    static var ageSeconds: TimeInterval? {
        let ts = UserDefaults.standard.double(forKey: timestampKey)
        guard ts > 0 else { return nil }
        return Date().timeIntervalSince1970 - ts
    }

    static var isExpired: Bool {
        guard let age = ageSeconds else { return true }
        return age > defaultMaxAge
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        UserDefaults.standard.removeObject(forKey: macKey)
    }
}
