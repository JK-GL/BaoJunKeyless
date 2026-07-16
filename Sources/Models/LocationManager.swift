import Foundation
import CoreLocation

// MARK: - GPS + 磁力计管理器
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let addressSettings: AddressServiceSettings
    private let displayCacheStore: VehicleDisplayCacheStore

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

    /// 已连车机 BLE 时的离车距离覆盖（米）。地下车库 GPS 漂时优先用这个。
    /// nil = 回落 GPS。
    private var bleDistanceOverrideMeters: CLLocationDistance?
    /// 对外只读：当前用于展示/雷达的有效距离（BLE 优先）
    @Published private(set) var effectiveDistance: CLLocationDistance = 0
    @Published private(set) var distanceSource: String = "gps" // gps / ble / cache

    private var lastRadarDistance: CLLocationDistance = -1
    private var lastRadarRelativeAngle: CLLocationDirection = -1
    private var lastPublishedDistance: CLLocationDistance = -1
    /// 指南针节流：过密 heading 会拖主线程，雷达跟手转不需要逐度刷新。
    private var lastAcceptedHeading: CLLocationDirection = -1
    private var lastHeadingAcceptedAt: CFTimeInterval = 0
    private let headingMinDeltaDegrees: CLLocationDirection = 1.2
    private let headingMinInterval: CFTimeInterval = 1.0 / 24.0
    private let radarAnglePushMinDegrees: CLLocationDirection = 1.0
    private let radarDistancePushMinMeters: CLLocationDistance = 0.35

    init(
        addressSettings: AddressServiceSettings = .shared,
        displayCacheStore: VehicleDisplayCacheStore = VehicleDisplayCacheStore()
    ) {
        self.addressSettings = addressSettings
        self.displayCacheStore = displayCacheStore
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        // 系统先滤掉 <1.5° 的抖动；业务侧再做时间/角度节流。
        manager.headingFilter = 1.5
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
        // 雷达只靠指南针航向；陀螺仪不参与。这里做角度+时间节流，避免高频 recalculate。
        let nextHeading = newHeading.magneticHeading
        guard nextHeading >= 0 else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let delta: CLLocationDirection
        if lastAcceptedHeading < 0 {
            delta = .greatestFiniteMagnitude
        } else {
            delta = angleDelta(nextHeading, lastAcceptedHeading)
        }

        // 大转向立即跟；小抖动需间隔足够才更新。
        let intervalOK = (now - lastHeadingAcceptedAt) >= headingMinInterval
        let significantTurn = delta >= headingMinDeltaDegrees
        guard lastAcceptedHeading < 0 || significantTurn || (intervalOK && delta >= 0.6) else {
            return
        }

        heading = nextHeading
        lastAcceptedHeading = nextHeading
        lastHeadingAcceptedAt = now
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

    /// 由 BLE RSSI 估算写入；传 nil 清除覆盖，回落 GPS。
    func setBLEDistanceOverride(_ meters: CLLocationDistance?) {
        let normalized: CLLocationDistance?
        if let meters {
            normalized = min(max(meters, 0.3), BLEProximityDistanceEstimator.maxTrustedMeters)
        } else {
            normalized = nil
        }
        let changed: Bool
        if let a = bleDistanceOverrideMeters, let b = normalized {
            changed = abs(a - b) >= 0.15
        } else {
            changed = bleDistanceOverrideMeters != normalized
        }
        bleDistanceOverrideMeters = normalized
        if changed {
            publishEffectiveDistance(force: true)
            // 同步雷达点位距离（方位仍用 GPS/罗盘，距离用 BLE）
            if let meters = normalized {
                applyRadarDistance(meters)
            } else {
                recalculate()
            }
        }
    }

    // MARK: - 计算距离、方位、相对角度
    private func recalculate() {
        guard let phone = phoneLocation else {
            publishEffectiveDistance(force: false)
            return
        }
        guard carLatitudeGcj != 0 || carLongitudeGcj != 0 else {
            if lastPublishedDistance != 0 {
                distance = 0
                lastPublishedDistance = 0
            }
            publishEffectiveDistance(force: true)
            return
        }

        let phoneGcj = LocationResolver.wgs84ToGcj02(lat: phone.coordinate.latitude, lng: phone.coordinate.longitude)
        let phoneLoc = CLLocation(latitude: phoneGcj.lat, longitude: phoneGcj.lng)
        let carLoc = CLLocation(latitude: carLatitudeGcj, longitude: carLongitudeGcj)
        let gpsDistance = phoneLoc.distance(from: carLoc)

        let nextBearing = calculateBearing(from: phoneLoc, to: carLoc)
        let nextRelativeAngle = normalizeAngle(nextBearing - heading)

        // 有 BLE 覆盖时：雷达距离用 BLE，方位仍用 GPS/罗盘
        let nextDistance = bleDistanceOverrideMeters ?? gpsDistance

        var radarChanged = false
        if lastRadarDistance < 0 || abs(nextDistance - lastRadarDistance) >= radarDistancePushMinMeters {
            radarDistance = nextDistance
            lastRadarDistance = nextDistance
            radarChanged = true
        }

        // 角度推送阈值略放宽：1° 内肉眼难辨，却会触发车标 displayLink。
        if lastRadarRelativeAngle < 0 || angleDelta(nextRelativeAngle, lastRadarRelativeAngle) >= radarAnglePushMinDegrees {
            radarRelativeAngle = nextRelativeAngle
            lastRadarRelativeAngle = nextRelativeAngle
            radarChanged = true
        }

        if radarChanged, lastRadarDistance >= 0, lastRadarRelativeAngle >= 0 {
            radarPositionHandler?(radarDistance, radarRelativeAngle)
        }

        // GPS 距离始终更新到 distance 字段（供无 BLE 时展示）
        if lastPublishedDistance < 0 || abs(gpsDistance - lastPublishedDistance) >= 0.5 {
            distance = gpsDistance
            lastPublishedDistance = gpsDistance
            // 仅在无 BLE 覆盖时缓存 GPS 距离，避免地库错误值污染
            if bleDistanceOverrideMeters == nil {
                displayCacheStore.setDistance(gpsDistance)
            }
        }
        publishEffectiveDistance(force: false)
    }

    private func applyRadarDistance(_ meters: CLLocationDistance) {
        var radarChanged = false
        if lastRadarDistance < 0 || abs(meters - lastRadarDistance) >= 0.15 {
            radarDistance = meters
            lastRadarDistance = meters
            radarChanged = true
        }
        if radarChanged, lastRadarRelativeAngle >= 0 {
            radarPositionHandler?(radarDistance, radarRelativeAngle)
        } else if radarChanged {
            // 尚无角度时也推一次 0 角，避免完全不刷新
            radarPositionHandler?(radarDistance, radarRelativeAngle)
        }
        // BLE 近距也写缓存，便于断连瞬间不跳到错误 GPS
        displayCacheStore.setDistance(meters)
        publishEffectiveDistance(force: true)
    }

    private func publishEffectiveDistance(force: Bool) {
        let next: CLLocationDistance
        let source: String
        if let ble = bleDistanceOverrideMeters {
            next = ble
            source = "ble"
        } else if distance > 0 {
            next = distance
            source = "gps"
        } else {
            let cached = displayCacheStore.loadSnapshot().distanceMeters
            next = cached
            source = cached > 0 ? "cache" : "gps"
        }
        if force || abs(next - effectiveDistance) >= 0.15 || source != distanceSource {
            effectiveDistance = next
            distanceSource = source
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
        // CrashLogger.shared.mark("Location", "pause") // routine
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func resume() {
        // CrashLogger.shared.mark("Location", "resume") // routine
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        requestCurrentLocationIfPossible()
    }

    deinit {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}
