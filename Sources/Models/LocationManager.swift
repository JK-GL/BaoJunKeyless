import Foundation
import CoreLocation

// MARK: - GPS + 磁力计管理器
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private var phoneLocation: CLLocation?
    private var heading: CLLocationDirection = 0  // 手机朝向角度

    // 车辆坐标（显示层统一使用 GCJ-02）
    private var carLatitudeGcj: Double = 0
    private var carLongitudeGcj: Double = 0

    // 雷达内部状态：不走 @Published，避免高频 heading 让 SwiftUI 反复刷新。
    private(set) var radarDistance: CLLocationDistance = 0
    private(set) var radarRelativeAngle: CLLocationDirection = 0
    var radarPositionHandler: ((CLLocationDistance, CLLocationDirection) -> Void)?

    // UI 文字只需要低频更新。
    @Published private(set) var distance: CLLocationDistance = 0
    @Published private(set) var vehicleAddress: String = ""

    private var lastRadarDistance: CLLocationDistance = -1
    private var lastRadarRelativeAngle: CLLocationDirection = -1
    private var lastPublishedDistance: CLLocationDistance = -1

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.headingFilter = kCLHeadingFilterNone
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        requestCurrentLocationIfPossible()
    }

    // MARK: - 设置车辆坐标（GCJ-02）
    func setCarLocation(lat: Double, lng: Double, address: String? = nil) {
        carLatitudeGcj = lat
        carLongitudeGcj = lng
        requestCurrentLocationIfPossible()
        recalculate()

        if let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vehicleAddress = address
            return
        }

        if vehicleAddress.isEmpty {
            vehicleAddress = LocationResolver.shared.cachedAddress ?? ""
        }

        let addressSettings = AddressServiceSettings()
        LocationResolver.shared.getAddress(
            gcjLat: lat,
            gcjLng: lng,
            address: address,
            amapWebKey: addressSettings.amapWebKey
        ) { [weak self] resolved in
            guard let self else { return }
            if let resolved {
                self.vehicleAddress = resolved
            }
        }
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        phoneLocation = locations.last
        recalculate()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.magneticHeading
        recalculate()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            requestCurrentLocationIfPossible()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        CrashLogger.shared.mark("Location", "update failed", details: error.localizedDescription)
    }

    // MARK: - 计算距离、方位、相对角度
    private func recalculate() {
        guard let phone = phoneLocation else { return }
        guard carLatitudeGcj != 0 || carLongitudeGcj != 0 else {
            if lastPublishedDistance != 0 {
                distance = 0
                lastPublishedDistance = 0
            }
            return
        }

        let phoneGcj = LocationResolver.wgs84ToGcj02(lat: phone.coordinate.latitude, lng: phone.coordinate.longitude)
        let phoneLoc = CLLocation(latitude: phoneGcj.lat, longitude: phoneGcj.lng)
        let carLoc = CLLocation(latitude: carLatitudeGcj, longitude: carLongitudeGcj)
        let nextDistance = phoneLoc.distance(from: carLoc)

        let nextBearing = calculateBearing(from: phoneLoc, to: carLoc)
        let nextRelativeAngle = normalizeAngle(nextBearing - heading)

        var radarChanged = false
        if lastRadarDistance < 0 || abs(nextDistance - lastRadarDistance) >= 0.25 {
            radarDistance = nextDistance
            lastRadarDistance = nextDistance
            radarChanged = true
        }

        if lastRadarRelativeAngle < 0 || angleDelta(nextRelativeAngle, lastRadarRelativeAngle) >= 0.25 {
            radarRelativeAngle = nextRelativeAngle
            lastRadarRelativeAngle = nextRelativeAngle
            radarChanged = true
        }

        if radarChanged, lastRadarDistance >= 0, lastRadarRelativeAngle >= 0 {
            radarPositionHandler?(radarDistance, radarRelativeAngle)
        }

        if lastPublishedDistance < 0 || abs(nextDistance - lastPublishedDistance) >= 0.5 {
            distance = nextDistance
            lastPublishedDistance = nextDistance
            UserDefaults.standard.set(nextDistance, forKey: "LastDistanceMeters")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "LastDistanceTs")
        }
    }

    // MARK: - Haversine 方位角计算
    private func calculateBearing(from: CLLocation, to: CLLocation) -> CLLocationDirection {
        let lat1 = from.coordinate.latitude * .pi / 180
        let lat2 = to.coordinate.latitude * .pi / 180
        let dLon = (to.coordinate.longitude - from.coordinate.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return normalizeAngle(bearing)
    }

    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }

    private func requestCurrentLocationIfPossible() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func forceRequestCurrentLocation() {
        requestCurrentLocationIfPossible()
    }

    // ⭐ 前后台切换
    func pause() {
        CrashLogger.shared.mark("Location", "pause")
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func resume() {
        CrashLogger.shared.mark("Location", "resume")
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        requestCurrentLocationIfPossible()
    }

    deinit {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}
