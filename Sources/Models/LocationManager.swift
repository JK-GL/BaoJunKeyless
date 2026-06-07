import Foundation
import CoreLocation

// MARK: - GPS + 磁力计管理器
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private var phoneLocation: CLLocation?
    private var heading: CLLocationDirection = 0  // 手机朝向角度

    // 车辆坐标（从 MQTT/API 获取后设置）
    private var carLatitude: Double = 0
    private var carLongitude: Double = 0

    // 雷达内部状态：不走 @Published，避免高频 heading 让 SwiftUI 反复刷新。
    private(set) var radarDistance: CLLocationDistance = 0
    private(set) var radarRelativeAngle: CLLocationDirection = 0
    var radarPositionHandler: ((CLLocationDistance, CLLocationDirection) -> Void)?

    // UI 文字只需要低频更新。
    @Published private(set) var distance: CLLocationDistance = 0
    @Published private(set) var vehicleAddress: String = ""

    private let geocoder = CLGeocoder()
    private var lastReverseGeocodedCoordinate: CLLocationCoordinate2D?
    private var lastReverseGeocodedDate: Date?
    private var externalFallbackAddress: String?
    private var reverseGeocodeInFlight = false

    private var lastRadarDistance: CLLocationDistance = -1
    private var lastRadarRelativeAngle: CLLocationDirection = -1
    private var lastPublishedDistance: CLLocationDistance = -1

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
    func setCarLocation(lat: Double, lng: Double, address: String? = nil) {
        carLatitude = lat
        carLongitude = lng

        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAddress, !trimmedAddress.isEmpty {
            externalFallbackAddress = trimmedAddress
        }

        recalculate()
        reverseGeocodeCarCoordinateIfNeeded(force: vehicleAddress.isEmpty)
    }

    private func reverseGeocodeCarCoordinateIfNeeded(force: Bool = false) {
        let coordinate = CLLocationCoordinate2D(latitude: carLatitude, longitude: carLongitude)
        guard carLatitude != 0 || carLongitude != 0 else { return }
        guard !reverseGeocodeInFlight else { return }

        let now = Date()
        let distanceFromLast: Double
        if let last = lastReverseGeocodedCoordinate {
            distanceFromLast = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        } else {
            distanceFromLast = .greatestFiniteMagnitude
        }

        let elapsed = lastReverseGeocodedDate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let needsUpdate = force || distanceFromLast >= 50 || elapsed >= 60
        guard needsUpdate else { return }

        reverseGeocodeInFlight = true
        geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { [weak self] placemarks, _ in
            guard let self else { return }
            self.reverseGeocodeInFlight = false
            self.lastReverseGeocodedCoordinate = coordinate
            self.lastReverseGeocodedDate = Date()

            let resolved = placemarks?.first.flatMap { Self.formattedAddress(from: $0) }
            let finalAddress = resolved
                ?? self.externalFallbackAddress
                ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)

            DispatchQueue.main.async {
                self.vehicleAddress = finalAddress
            }
        }
    }

    static func formattedAddress(from placemark: CLPlacemark) -> String? {
        var parts: [String] = []

        if let administrativeArea = placemark.administrativeArea {
            parts.append(administrativeArea)
        }

        if let locality = placemark.locality {
            if parts.last != locality {
                parts.append(locality)
            }
        }

        if let subLocality = placemark.subLocality {
            if parts.last != subLocality {
                parts.append(subLocality)
            }
        }

        if let thoroughfare = placemark.thoroughfare {
            if parts.last != thoroughfare {
                parts.append(thoroughfare)
            }
        }

        if let subThoroughfare = placemark.subThoroughfare {
            if parts.last != subThoroughfare {
                parts.append(subThoroughfare)
            }
        }

        if let name = placemark.name, !name.isEmpty {
            if parts.last != name {
                parts.append(name)
            }
        }

        let address = parts.joined()
        return address.isEmpty ? nil : address
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

        // 保留连续 heading 采样，但不要把每个微小传感器抖动都发布给 SwiftUI。
        // 雷达位置直接回调给 UIKit 视图；距离文字才低频 @Published 给 SwiftUI。
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

        if lastPublishedDistance < 0 || abs(nextDistance - lastPublishedDistance) >= 1.0 {
            distance = nextDistance
            lastPublishedDistance = nextDistance
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
