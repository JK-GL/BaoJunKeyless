import Foundation

/// 缓存最近一次 ble/key/query 返回的 BLE 钥匙材料，支持离线 BLE。
/// 官方 App 可以离线用蓝牙的原因就是本地缓存了这份材料。
enum VehicleBLEKeyCacheStore {
    private static let cacheKey = "VehicleBLE.KeyCache"
    private static let timestampKey = "VehicleBLE.KeyCache.Timestamp"
    private static let macKey = "VehicleBLE.KeyCache.Mac"

    static func save(_ info: [String: String]) {
        let filtered = info.filter { !$0.value.isEmpty }
        guard let data = try? JSONSerialization.data(withJSONObject: filtered, options: []) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
        if let mac = filtered["bleMac"] ?? filtered["macAddress"], !mac.isEmpty {
            UserDefaults.standard.set(mac, forKey: macKey)
        }
    }

    static func load() -> [String: String]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else { return nil }
        return dict.filter { !$0.value.isEmpty }
    }

    static var cachedMac: String? {
        UserDefaults.standard.string(forKey: macKey)
    }

    static var ageSeconds: TimeInterval? {
        let ts = UserDefaults.standard.double(forKey: timestampKey)
        guard ts > 0 else { return nil }
        return Date().timeIntervalSince1970 - ts
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        UserDefaults.standard.removeObject(forKey: macKey)
    }
}
