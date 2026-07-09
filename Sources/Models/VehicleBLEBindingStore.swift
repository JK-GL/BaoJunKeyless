import Foundation

struct VehicleBLEBinding: Codable, Equatable {
    let peripheralIdentifier: String
    let peripheralName: String
    let keyId: String
    let bleMacSuffix: String
    let boundAt: Date
    let lastAuthAt: Date

    var shortIdentifier: String {
        String(peripheralIdentifier.prefix(8))
    }

    var displaySummary: String {
        let name = peripheralName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--" : peripheralName
        let suffix = bleMacSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "--" : bleMacSuffix
        return "\(name) · id=\(shortIdentifier) · macSuffix=\(suffix)"
    }
}

enum VehicleBLEBindingStore {
    private static let key = "VehicleBLE.BoundPeripheral"
    /// 绑定最长有效期：30 天未再鉴权成功则失效
    static let maxIdleAge: TimeInterval = 30 * 24 * 60 * 60

    static func load() -> VehicleBLEBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let binding = try? JSONDecoder().decode(VehicleBLEBinding.self, from: data) else {
            clear()
            return nil
        }
        // 长时间未再鉴权成功，视为脏绑定
        if Date().timeIntervalSince(binding.lastAuthAt) > maxIdleAge {
            clear()
            return nil
        }
        return binding
    }

    static func save(_ binding: VehicleBLEBinding) {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 校验绑定是否仍匹配当前会话 key/mac；不匹配则清理并返回 nil
    static func loadMatching(keyId: String, bleMac: String) -> VehicleBLEBinding? {
        guard let binding = load() else { return nil }
        let expectedKey = normalizedToken(keyId)
        let expectedMacSuffix = macSuffix(bleMac)
        let boundKey = normalizedToken(binding.keyId)
        let boundMac = normalizedToken(binding.bleMacSuffix)

        let keyOK = expectedKey.isEmpty || boundKey.isEmpty || expectedKey == boundKey
        let macOK = expectedMacSuffix.isEmpty || boundMac.isEmpty || expectedMacSuffix == boundMac || expectedMacSuffix.hasSuffix(boundMac) || boundMac.hasSuffix(expectedMacSuffix)
        if keyOK && macOK {
            return binding
        }
        clear()
        return nil
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func macSuffix(_ mac: String) -> String {
        let normalized = normalizedToken(mac)
        guard !normalized.isEmpty else { return "" }
        return String(normalized.suffix(6))
    }
}
