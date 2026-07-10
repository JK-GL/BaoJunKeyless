import Foundation
import Combine

final class VehicleBLEKeyInfoStore: ObservableObject {
    static let shared = VehicleBLEKeyInfoStore()

    @Published var latestBleKeyInfo: [String: String] = [:]

    func replace(with info: [String: String]) {
        latestBleKeyInfo = info
    }

    func clear() {
        latestBleKeyInfo = [:]
    }

    var isEmpty: Bool {
        latestBleKeyInfo.isEmpty
    }

    subscript(key: String) -> String? {
        get { latestBleKeyInfo[key] }
        set {
            var next = latestBleKeyInfo
            next[key] = newValue
            latestBleKeyInfo = next
        }
    }
}
