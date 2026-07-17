import Foundation

/// 缓存最近一次 ble/key/query 返回的 BLE 钥匙材料，支持离线 BLE。
/// 缓存策略：
/// 1. 不做 7 天 TTL 自动过期；
/// 2. 按 userId(phone) + vin 隔离；
/// 3. 主体放 Keychain，避免凭证类材料明文落 UserDefaults；
/// 4. 登出/清配置时清当前作用域缓存。
enum VehicleBLEKeyCacheStore {
    private static let keychainService = "com.baojun.keyless.ble-key-cache"
    private static let lastActiveAccountKey = "VehicleBLE.KeyCache.LastActiveAccount"

    // 兼容 v598 之前的单槽 UserDefaults 缓存；迁移成功后即清理。
    private static let legacyCacheKey = "VehicleBLE.KeyCache"
    private static let legacyTimestampKey = "VehicleBLE.KeyCache.Timestamp"
    private static let legacyMacKey = "VehicleBLE.KeyCache.Mac"

    static func save(_ info: [String: String], vin: String, phone: String) {
        guard let account = account(vin: vin, phone: phone) else { return }
        let filtered = sanitized(info)
        guard !filtered.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: filtered, options: []),
              let payload = String(data: data, encoding: .utf8) else {
            return
        }
        guard KeychainStringStore.write(payload, service: keychainService, account: account) else { return }
        activate(account: account)
        clearLegacy()
    }

    static func load(vin: String, phone: String) -> [String: String]? {
        guard let account = account(vin: vin, phone: phone) else { return nil }
        migrateLegacyIfNeeded(into: account)
        activate(account: account)
        return load(account: account)
    }

    static func loadLastActive() -> [String: String]? {
        if let account = UserDefaults.standard.string(forKey: lastActiveAccountKey),
           let cached = load(account: account) {
            return cached
        }
        return loadLegacyPayload()
    }

    static func clear(vin: String, phone: String) {
        guard let account = account(vin: vin, phone: phone) else { return }
        KeychainStringStore.delete(service: keychainService, account: account)
        if UserDefaults.standard.string(forKey: lastActiveAccountKey) == account {
            UserDefaults.standard.removeObject(forKey: lastActiveAccountKey)
        }
        clearLegacy()
    }

    static func clearLastActive() {
        if let account = UserDefaults.standard.string(forKey: lastActiveAccountKey) {
            KeychainStringStore.delete(service: keychainService, account: account)
        }
        UserDefaults.standard.removeObject(forKey: lastActiveAccountKey)
        clearLegacy()
    }

    private static func load(account: String) -> [String: String]? {
        guard let payload = KeychainStringStore.read(service: keychainService, account: account),
              let data = payload.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            return nil
        }
        let filtered = sanitized(dict)
        return filtered.isEmpty ? nil : filtered
    }

    private static func account(vin: String, phone: String) -> String? {
        let normalizedPhone = normalizedToken(phone)
        let normalizedVIN = normalizedToken(vin)
        guard !normalizedPhone.isEmpty, !normalizedVIN.isEmpty else { return nil }
        return "\(normalizedPhone)|\(normalizedVIN)"
    }

    private static func sanitized(_ info: [String: String]) -> [String: String] {
        info.reduce(into: [String: String]()) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partial[key] = value
        }
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func migrateLegacyIfNeeded(into account: String) {
        guard load(account: account) == nil,
              let legacy = loadLegacyPayload() else { return }
        let filtered = sanitized(legacy)
        guard !filtered.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: filtered, options: []),
              let payload = String(data: data, encoding: .utf8),
              KeychainStringStore.write(payload, service: keychainService, account: account) else {
            return
        }
        activate(account: account)
        clearLegacy()
    }

    private static func loadLegacyPayload() -> [String: String]? {
        guard let data = UserDefaults.standard.data(forKey: legacyCacheKey),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String] else {
            return nil
        }
        let filtered = sanitized(dict)
        return filtered.isEmpty ? nil : filtered
    }

    private static func activate(account: String) {
        if let previous = UserDefaults.standard.string(forKey: lastActiveAccountKey), previous != account {
            KeychainStringStore.delete(service: keychainService, account: previous)
        }
        UserDefaults.standard.set(account, forKey: lastActiveAccountKey)
    }

    private static func clearLegacy() {
        UserDefaults.standard.removeObject(forKey: legacyCacheKey)
        UserDefaults.standard.removeObject(forKey: legacyTimestampKey)
        UserDefaults.standard.removeObject(forKey: legacyMacKey)
    }
}
