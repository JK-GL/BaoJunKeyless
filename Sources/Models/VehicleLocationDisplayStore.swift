import Foundation
import Combine

final class VehicleLocationDisplayStore: ObservableObject {
    static let shared = VehicleLocationDisplayStore()

    @Published var cachedLatitudeGcj: Double = 0
    @Published var cachedLongitudeGcj: Double = 0
    @Published var cachedAddress: String = ""
    @Published var liveLatitudeGcj: Double = 0
    @Published var liveLongitudeGcj: Double = 0
    @Published var liveAddress: String = ""

    var displayLatitudeGcj: Double {
        liveLatitudeGcj != 0 ? liveLatitudeGcj : cachedLatitudeGcj
    }

    var displayLongitudeGcj: Double {
        liveLongitudeGcj != 0 ? liveLongitudeGcj : cachedLongitudeGcj
    }

    var displayAddress: String {
        let live = liveAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return cachedAddress
    }

    func applyCachedCoordinate(latitudeGcj: Double, longitudeGcj: Double) {
        guard latitudeGcj != 0, longitudeGcj != 0 else { return }
        cachedLatitudeGcj = latitudeGcj
        cachedLongitudeGcj = longitudeGcj
    }

    func applyCachedAddress(_ address: String) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        cachedAddress = normalized
    }

    func applyLiveCoordinate(latitudeGcj: Double, longitudeGcj: Double, addressHint: String? = nil) {
        guard latitudeGcj != 0, longitudeGcj != 0 else { return }
        liveLatitudeGcj = latitudeGcj
        liveLongitudeGcj = longitudeGcj
        cachedLatitudeGcj = latitudeGcj
        cachedLongitudeGcj = longitudeGcj
        if let addressHint {
            let normalized = addressHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                liveAddress = normalized
                cachedAddress = normalized
            }
        }
    }

    func applyResolvedAddress(_ address: String) {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        liveAddress = normalized
        cachedAddress = normalized
    }
}
