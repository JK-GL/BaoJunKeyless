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

    static func load() -> VehicleBLEBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(VehicleBLEBinding.self, from: data)
    }

    static func save(_ binding: VehicleBLEBinding) {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
