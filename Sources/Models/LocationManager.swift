import Foundation
import CoreLocation

// MARK: - GPS + 磁力计管理器
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var phoneLocation: CLLocation?
    @Published var heading: CLLocationDirection = 0  // 手机朝向角度

    // 车辆坐标（从 MQTT/API 获取后设置）
    @Published var carLatitude: Double = 0
    @Published var carLongitude: Double = 0

    // 计算结果
    @Published var distance: CLLocationDistance = 0   // 距离（米）
    @Published var bearing: CLLocationDirection = 0   // 方位角（度）
    @Published var relativeAngle: CLLocationDirection = 0  // 相对角度（雷达上显示）

    private var lastPublishedDistance: CLLocationDistance = -1
    private var lastPublishedBearing: CLLocationDirection = -1
    private var lastPublishedRelativeAngle: CLLocationDirection = -1

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10      // ⭐ 移动 10 米以上才更新 GPS
        manager.headingFilter = kCLHeadingFilterNone  // ⭐ 方位连续更新，避免雷达车图 5° 一跳导致卡顿
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    // MARK: - 设置车辆坐标
    func setCarLocation(lat: Double, lng: Double) {
        carLatitude = lat
        carLongitude = lng
        recalculate()
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

    // MARK: - 计算距离、方位、相对角度
    private func recalculate() {
        guard let phone = phoneLocation else { return }

        let carLoc = CLLocation(latitude: carLatitude, longitude: carLongitude)
        let nextDistance = phone.distance(from: carLoc)

        // 方位角：从手机到车辆
        let nextBearing = calculateBearing(from: phone, to: carLoc)

        // 相对角度：车辆方位 - 手机朝向（映射到雷达 360°）
        let nextRelativeAngle = normalizeAngle(nextBearing - heading)

        if lastPublishedDistance < 0 || abs(nextDistance - lastPublishedDistance) >= 0.20 {
            distance = nextDistance
            lastPublishedDistance = nextDistance
        }

        if lastPublishedBearing < 0 || angleDelta(nextBearing, lastPublishedBearing) >= 0.10 {
            bearing = nextBearing
            lastPublishedBearing = nextBearing
        }

        if lastPublishedRelativeAngle < 0 || angleDelta(nextRelativeAngle, lastPublishedRelativeAngle) >= 0.10 {
            relativeAngle = nextRelativeAngle
            lastPublishedRelativeAngle = nextRelativeAngle
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
    }

    deinit {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}
