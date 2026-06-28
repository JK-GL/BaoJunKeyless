import Foundation

// MARK: - 地址服务设置
final class AddressServiceSettings: ObservableObject {
    static let shared = AddressServiceSettings()

    var amapWebKey: String {
        UserDefaults.standard.string(forKey: AppDefaultsKey.AddressService.amapWebKey) ?? ""
    }

    var displayAmapWebKey: String {
        let key = amapWebKey
        if key.isEmpty { return "未填写" }
        return String(key.prefix(4) + "***" + String(key.suffix(4)))
    }

    var hasAmapWebKey: Bool {
        !amapWebKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    func setAmapWebKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: AppDefaultsKey.AddressService.amapWebKey)
        CrashLogger.shared.mark("AddressService", "amapKey", details: trimmed.isEmpty ? "cleared" : "***")
    }

    func clearAmapWebKey() {
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.AddressService.amapWebKey)
        CrashLogger.shared.mark("AddressService", "amapKey", details: "cleared")
    }

    func reset() {
        clearAmapWebKey()
    }
}
