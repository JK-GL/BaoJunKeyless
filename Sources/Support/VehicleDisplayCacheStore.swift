import Foundation

// MARK: - 地址 / 距离显示缓存存储
final class VehicleDisplayCacheStore {
    struct Snapshot {
        let address: String
        let latitudeGcj: Double
        let longitudeGcj: Double
        let distanceMeters: Double
        let distanceTimestamp: TimeInterval
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSnapshot() -> Snapshot {
        Snapshot(
            address: defaults.string(forKey: AppDefaultsKey.VehicleCache.lastAddress)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            latitudeGcj: defaults.double(forKey: AppDefaultsKey.VehicleCache.lastLatitude),
            longitudeGcj: defaults.double(forKey: AppDefaultsKey.VehicleCache.lastLongitude),
            distanceMeters: defaults.object(forKey: AppDefaultsKey.VehicleCache.lastDistanceMeters) as? Double ?? 0,
            distanceTimestamp: defaults.object(forKey: AppDefaultsKey.VehicleCache.lastDistanceTimestamp) as? TimeInterval ?? 0
        )
    }

    func setAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppDefaultsKey.VehicleCache.lastAddress)
        } else {
            defaults.set(trimmed, forKey: AppDefaultsKey.VehicleCache.lastAddress)
        }
    }

    func setCoordinate(latitudeGcj: Double, longitudeGcj: Double) {
        defaults.set(latitudeGcj, forKey: AppDefaultsKey.VehicleCache.lastLatitude)
        defaults.set(longitudeGcj, forKey: AppDefaultsKey.VehicleCache.lastLongitude)
    }

    func setDistance(_ distanceMeters: Double, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        defaults.set(distanceMeters, forKey: AppDefaultsKey.VehicleCache.lastDistanceMeters)
        defaults.set(timestamp, forKey: AppDefaultsKey.VehicleCache.lastDistanceTimestamp)
    }
}
