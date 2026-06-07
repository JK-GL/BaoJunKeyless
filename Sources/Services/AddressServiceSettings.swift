import Foundation

// MARK: - 地址服务设置
enum AddressServiceType: String, CaseIterable, Identifiable {
    case apple = "apple"
    case amap = "amap"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple CLGeocoder"
        case .amap: return "高德 Web API"
        }
    }
}

final class AddressServiceSettings: ObservableObject {
    private let providerKey = "AddressService.Provider"
    private let amapKey = "AddressService.AmapWebKey"

    @Published var provider: AddressServiceType {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
            CrashLogger.shared.mark("AddressService", "provider", details: provider.rawValue)
        }
    }

    var amapWebKey: String {
        UserDefaults.standard.string(forKey: amapKey) ?? ""
    }

    var displayAmapWebKey: String {
        let key = amapWebKey
        if key.isEmpty { return "未填写" }
        return String(key.prefix(4) + "***" + String(key.suffix(4)))
    }

    var hasAmapWebKey: Bool {
        !amapWebKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: providerKey) ?? AddressServiceType.apple.rawValue
        self.provider = AddressServiceType(rawValue: saved) ?? .apple
    }

    func setAmapWebKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: amapKey)
        CrashLogger.shared.mark("AddressService", "amapKey", details: trimmed.isEmpty ? "cleared" : "***")
    }

    func clearAmapWebKey() {
        UserDefaults.standard.removeObject(forKey: amapKey)
        CrashLogger.shared.mark("AddressService", "amapKey", details: "cleared")
    }

    func reset() {
        provider = .apple
        clearAmapWebKey()
    }
}
