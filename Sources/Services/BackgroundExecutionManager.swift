import Foundation
import CoreLocation
import UIKit
import Combine

/// 后台增强运行时：
/// - 增强后台执行（background task）
/// - 电子围栏预唤醒
/// - 按需定位保活
/// - 受限提醒
/// 注意：围栏只负责调度，不直接解锁/上锁。
final class BackgroundExecutionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BackgroundExecutionManager()

    enum RuntimePhase: String {
        case idleDisabled = "已停用"
        case fenceSleep = "围栏休眠"
        case approachArming = "警戒中"
        case bleActive = "BLE 活跃"
        case keylessAuthenticated = "已鉴权无感"
        case degraded = "后台受限"
    }

    @Published private(set) var phase: RuntimePhase = .idleDisabled
    @Published private(set) var isInGeofence = false
    @Published private(set) var isKeepAliveActive = false
    @Published private(set) var lastLimitationReason: String?

    private let locationManager = CLLocationManager()
    private let regionIdentifier = "com.sgmw.key.vehicle.geofence"
    private let settingsStore = KeylessSettingsStore.shared
    private let locationDisplayStore = VehicleLocationDisplayStore.shared
    private let connectionStatusStore = VehicleConnectionStatusStore.shared

    private var cancellables = Set<AnyCancellable>()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var monitoredRegion: CLCircularRegion?
    private var lastFenceCenter: CLLocationCoordinate2D?
    private var lastFenceRadius: CLLocationDistance = 0
    private var lastLimitationNotifyAt: Date?
    private var isAppInForeground = true
    private var keepAliveDesired = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 40
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.allowsBackgroundLocationUpdates = false
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = false
        }

        observeInputs()
        applySettings(settingsStore.settings, reason: "init")
    }

    // MARK: - Public API

    func handleDidEnterBackground() {
        isAppInForeground = false
        let settings = settingsStore.settings
        if settings.keylessEnabled && settings.backgroundEnhancedEnabled {
            beginBackgroundTask(reason: "keyless-background")
        }
        reevaluate(reason: "enter-background")
        if settings.keylessEnabled {
            requestBLESession(forceRestart: false, detail: "进入后台")
        }
    }

    func handleWillEnterForeground() {
        isAppInForeground = true
        endBackgroundTask()
        reevaluate(reason: "enter-foreground")
    }

    func applySettings(_ settings: KeylessSettings, reason: String = "settings") {
        if !settings.keylessEnabled {
            stopAll(reason: "无感关闭")
            phase = .idleDisabled
            return
        }

        requestAuthorizationIfNeeded(for: settings)
        updateGeofenceIfNeeded(settings: settings, force: reason.contains("settings") || reason.contains("radius"))
        reevaluate(reason: reason)
    }

    func notifyVehicleCoordinateChanged() {
        updateGeofenceIfNeeded(settings: settingsStore.settings, force: false)
        reevaluate(reason: "vehicle-location")
    }

    func notifyBLEStatusChanged() {
        reevaluate(reason: "ble-status")
    }

    // MARK: - Observe

    private func observeInputs() {
        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.applySettings(settings, reason: "settings-change")
            }
            .store(in: &cancellables)

        locationDisplayStore.$liveLatitudeGcj
            .combineLatest(locationDisplayStore.$liveLongitudeGcj, locationDisplayStore.$cachedLatitudeGcj, locationDisplayStore.$cachedLongitudeGcj)
            .receive(on: DispatchQueue.main)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.notifyVehicleCoordinateChanged()
            }
            .store(in: &cancellables)

        connectionStatusStore.$bleStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.notifyBLEStatusChanged()
            }
            .store(in: &cancellables)
    }

    // MARK: - Evaluate

    private func reevaluate(reason: String) {
        let settings = settingsStore.settings
        guard settings.keylessEnabled else {
            stopAll(reason: "无感关闭")
            phase = .idleDisabled
            return
        }

        let bleBusy = isBLEBusy
        let auth = connectionStatusStore.bleStatus == .authenticated

        // 权限不足 → 受限
        if (settings.geofenceWakeEnabled || settings.locationKeepAliveEnabled),
           !hasSufficientLocationPermission(for: settings) {
            enterDegraded(reason: "定位权限不足，后台预唤醒/保活受限")
            // 仍可尝试 BLE 后台，不强制停
        }

        // 定位保活：按需
        let wantKeepAlive =
            settings.locationKeepAliveEnabled
            && (isInGeofence || bleBusy || auth)
        setKeepAliveActive(wantKeepAlive)

        if auth {
            phase = .keylessAuthenticated
        } else if bleBusy {
            phase = .bleActive
        } else if isInGeofence {
            phase = .approachArming
            if settings.backgroundEnhancedEnabled && !isAppInForeground {
                beginBackgroundTask(reason: "approach-arming")
            }
        } else if settings.geofenceWakeEnabled, monitoredRegion != nil {
            phase = .fenceSleep
        } else if phase != .degraded {
            phase = .approachArming
        }

        CrashLogger.shared.mark(
            "BG",
            "reeval \(reason) phase=\(phase.rawValue) fence=\(isInGeofence ? 1 : 0) keepAlive=\(isKeepAliveActive ? 1 : 0) ble=\(String(describing: connectionStatusStore.bleStatus))"
        )
    }

    private var isBLEBusy: Bool {
        switch connectionStatusStore.bleStatus {
        case .scanning, .connecting, .connected, .authenticating, .authenticated:
            return true
        default:
            return false
        }
    }

    // MARK: - Geofence

    private func updateGeofenceIfNeeded(settings: KeylessSettings, force: Bool) {
        guard settings.keylessEnabled, settings.geofenceWakeEnabled else {
            removeGeofence(reason: "围栏关闭")
            return
        }

        guard let centerWGS = currentVehicleCoordinateWGS84() else {
            removeGeofence(reason: "车辆位置无效")
            return
        }

        let radius = KeylessSettings.clampedGeofenceRadius(settings.geofenceRadiusMeters)
        if !force,
           let last = lastFenceCenter,
           abs(last.latitude - centerWGS.latitude) < 0.00015,
           abs(last.longitude - centerWGS.longitude) < 0.00015,
           abs(lastFenceRadius - radius) < 1 {
            return
        }

        // 需要 Always 才能可靠后台围栏
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            enterDegraded(reason: "需要定位权限以启用电子围栏")
            return
        }

        let region = CLCircularRegion(center: centerWGS, radius: radius, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true

        // 先清旧再挂新
        for old in locationManager.monitoredRegions where old.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: old)
        }
        locationManager.startMonitoring(for: region)
        // 立即请求一次当前状态，避免进圈后才挂上导致漏唤醒
        locationManager.requestState(for: region)

        monitoredRegion = region
        lastFenceCenter = centerWGS
        lastFenceRadius = radius

        VehicleEventLogStore.shared.addThrottled(
            .keyless,
            "电子围栏已更新",
            detail: "半径 \(Int(radius)) 米 · 中心已同步车辆位置",
            identity: "geofence-update",
            minimumInterval: 20
        )
        CrashLogger.shared.mark("BG", "geofence updated r=\(Int(radius)) lat=\(String(format: "%.5f", centerWGS.latitude)) lng=\(String(format: "%.5f", centerWGS.longitude))")
    }

    private func removeGeofence(reason: String) {
        for old in locationManager.monitoredRegions where old.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: old)
        }
        if monitoredRegion != nil {
            CrashLogger.shared.mark("BG", "geofence removed: \(reason)")
        }
        monitoredRegion = nil
        lastFenceCenter = nil
        lastFenceRadius = 0
        if isInGeofence {
            isInGeofence = false
        }
    }

    private func currentVehicleCoordinateWGS84() -> CLLocationCoordinate2D? {
        let latGcj = locationDisplayStore.displayLatitudeGcj
        let lngGcj = locationDisplayStore.displayLongitudeGcj
        guard latGcj != 0, lngGcj != 0 else { return nil }
        // CoreLocation 围栏用 WGS-84；显示层是 GCJ-02
        let wgs = LocationResolver.gcj02ToWgs84(lat: latGcj, lng: lngGcj)
        guard abs(wgs.lat) <= 90, abs(wgs.lng) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: wgs.lat, longitude: wgs.lng)
    }

    // MARK: - Keep-alive / Background task

    private func setKeepAliveActive(_ active: Bool) {
        keepAliveDesired = active
        guard active else {
            if isKeepAliveActive {
                locationManager.allowsBackgroundLocationUpdates = false
                locationManager.stopUpdatingLocation()
                isKeepAliveActive = false
                CrashLogger.shared.mark("BG", "location keep-alive stop")
            }
            return
        }

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            enterDegraded(reason: "定位权限不足，无法开启定位保活")
            return
        }

        // Always 更稳；WhenInUse 时仍尝试（前台/短后台可能有效）
        locationManager.allowsBackgroundLocationUpdates = (status == .authorizedAlways)
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.startUpdatingLocation()
        if !isKeepAliveActive {
            isKeepAliveActive = true
            CrashLogger.shared.mark("BG", "location keep-alive start auth=\(status.rawValue)")
        }
    }

    private func beginBackgroundTask(reason: String) {
        guard settingsStore.settings.backgroundEnhancedEnabled else { return }
        if backgroundTaskID != .invalid { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SGMWKey.\(reason)") { [weak self] in
            self?.endBackgroundTask()
        }
        CrashLogger.shared.mark("BG", "beginBackgroundTask \(reason) id=\(backgroundTaskID.rawValue)")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        let id = backgroundTaskID
        backgroundTaskID = .invalid
        UIApplication.shared.endBackgroundTask(id)
        CrashLogger.shared.mark("BG", "endBackgroundTask id=\(id.rawValue)")
    }

    private func stopAll(reason: String) {
        removeGeofence(reason: reason)
        setKeepAliveActive(false)
        endBackgroundTask()
        isInGeofence = false
        CrashLogger.shared.mark("BG", "stopAll: \(reason)")
    }

    // MARK: - Permission / degraded

    private func requestAuthorizationIfNeeded(for settings: KeylessSettings) {
        let status = locationManager.authorizationStatus
        let needsBackgroundLocation = settings.geofenceWakeEnabled || settings.locationKeepAliveEnabled
        guard needsBackgroundLocation else { return }

        switch status {
        case .notDetermined:
            // 先 whenInUse，再在授权后尝试 always
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // 围栏/保活需要 always 更稳
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func hasSufficientLocationPermission(for settings: KeylessSettings) -> Bool {
        let status = locationManager.authorizationStatus
        if settings.geofenceWakeEnabled {
            // 围栏后台：Always 最佳；WhenInUse 仅前台有效
            return status == .authorizedAlways || status == .authorizedWhenInUse
        }
        if settings.locationKeepAliveEnabled {
            return status == .authorizedAlways || status == .authorizedWhenInUse
        }
        return true
    }

    private func enterDegraded(reason: String) {
        phase = .degraded
        lastLimitationReason = reason
        postLimitationNotificationIfNeeded(reason: reason)
        VehicleEventLogStore.shared.addThrottled(
            .warning,
            "后台能力受限",
            detail: reason,
            identity: "bg-degraded",
            minimumInterval: 60
        )
    }

    private func postLimitationNotificationIfNeeded(reason: String) {
        let now = Date()
        if let last = lastLimitationNotifyAt, now.timeIntervalSince(last) < 300 {
            return
        }
        lastLimitationNotifyAt = now
        AppNotificationManager.shared.postKeylessNotification(
            title: "无感后台受限",
            body: reason
        )
    }

    private func requestBLESession(forceRestart: Bool, detail: String) {
        guard let store = VehicleStateStoreBridge.current as? MQTTVehicleStateStore else { return }
        store.ensureBLESession(forceRestart: forceRestart, optimisticScanning: true)
        VehicleEventLogStore.shared.addThrottled(
            .keyless,
            "后台唤醒 BLE",
            detail: detail,
            identity: "bg-wake-ble",
            minimumInterval: 15
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        isInGeofence = true
        if settingsStore.settings.backgroundEnhancedEnabled {
            beginBackgroundTask(reason: "geofence-enter")
        }
        requestBLESession(forceRestart: false, detail: "进入电子围栏")
        // 后台状态同步：尝试保活 MQTT/HTTP
        if let store = VehicleStateStoreBridge.current as? MQTTVehicleStateStore {
            store.applyBackgroundRuntimeSettings(reason: "geofence-enter")
            if store.mqttStatus != .connected {
                store.reconnect()
            }
        }
        reevaluate(reason: "enter-region")
        VehicleEventLogStore.shared.add(.keyless, "进入电子围栏", detail: "启动蓝牙警戒（不直接解锁）")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        isInGeofence = false
        // 出圈不锁车；仅降功耗
        reevaluate(reason: "exit-region")
        VehicleEventLogStore.shared.add(.keyless, "离开电子围栏", detail: "降低后台活跃度（不自动上锁）")
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        switch state {
        case .inside:
            if !isInGeofence {
                isInGeofence = true
                reevaluate(reason: "region-state-inside")
            }
        case .outside:
            if isInGeofence {
                isInGeofence = false
                reevaluate(reason: "region-state-outside")
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        enterDegraded(reason: "电子围栏监控失败：\(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let settings = settingsStore.settings
        switch manager.authorizationStatus {
        case .authorizedAlways:
            updateGeofenceIfNeeded(settings: settings, force: true)
            reevaluate(reason: "auth-always")
        case .authorizedWhenInUse:
            // 尽量再要 Always
            if settings.geofenceWakeEnabled || settings.locationKeepAliveEnabled {
                manager.requestAlwaysAuthorization()
            }
            updateGeofenceIfNeeded(settings: settings, force: true)
            reevaluate(reason: "auth-when-in-use")
        case .denied, .restricted:
            enterDegraded(reason: "定位权限被拒绝，围栏/保活不可用")
            removeGeofence(reason: "权限拒绝")
            setKeepAliveActive(false)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 保活用途：不驱动无感决策，仅维持进程
        if keepAliveDesired, settingsStore.settings.backgroundEnhancedEnabled, !isAppInForeground {
            beginBackgroundTask(reason: "location-keepalive")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        CrashLogger.shared.mark("BG", "location fail: \(error.localizedDescription)")
    }
}
