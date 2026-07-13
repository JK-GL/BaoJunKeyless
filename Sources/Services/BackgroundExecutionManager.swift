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
/// 用户可见日志走 VehicleEventLogStore（可 ×N 合并）；CrashLogger 仅作底层诊断。
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
    private let eventLog = VehicleEventLogStore.shared

    private var cancellables = Set<AnyCancellable>()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var monitoredRegion: CLCircularRegion?
    private var lastFenceCenter: CLLocationCoordinate2D?
    private var lastFenceRadius: CLLocationDistance = 0
    private var lastLimitationNotifyAt: Date?
    private var isAppInForeground = true
    private var keepAliveDesired = false
    private var lastLoggedPhase: RuntimePhase?
    private var lastLoggedKeepAlive: Bool?
    private var lastLoggedInFence: Bool?

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
        logInfo(
            "进入后台",
            detail: settings.keylessEnabled ? "无感开启 · 尝试续命" : "无感关闭",
            identity: "bg-enter"
        )
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
        logInfo("回到前台", detail: "结束后台任务 · 恢复前台策略", identity: "bg-foreground")
        reevaluate(reason: "enter-foreground")
    }

    func applySettings(_ settings: KeylessSettings, reason: String = "settings") {
        if !settings.keylessEnabled {
            stopAll(reason: "无感关闭")
            phase = .idleDisabled
            logInfo("后台增强已停用", detail: "无感关闭", identity: "bg-disabled")
            return
        }

        requestAuthorizationIfNeeded(for: settings)
        updateGeofenceIfNeeded(settings: settings, force: reason.contains("settings") || reason.contains("radius") || reason == "init")
        reevaluate(reason: reason)
        // 仅围栏扫描等开关变化后，立刻让 BLE 会话重评估
        reapplyBLEScanPolicy(reason: reason)
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

        // 权限不足 → 受限（错误类）
        if (settings.geofenceWakeEnabled || settings.locationKeepAliveEnabled),
           !hasSufficientLocationPermission(for: settings) {
            enterDegraded(reason: "定位权限不足，后台预唤醒/保活受限")
        }

        // 定位保活：按需
        let wantKeepAlive =
            settings.locationKeepAliveEnabled
            && (isInGeofence || bleBusy || auth)
        setKeepAliveActive(wantKeepAlive)

        let previousPhase = phase
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

        // 阶段变化写用户日志（合并）
        if lastLoggedPhase != phase {
            lastLoggedPhase = phase
            if phase == .degraded {
                // 错误路径由 enterDegraded 写
            } else {
                logInfo(
                    "后台阶段",
                    detail: "\(phase.rawValue) · \(reasonText(reason))",
                    identity: "bg-phase|\(phase.rawValue)"
                )
            }
        } else if previousPhase != phase {
            // no-op
        }

        if lastLoggedInFence != isInGeofence {
            lastLoggedInFence = isInGeofence
        }
        if lastLoggedKeepAlive != isKeepAliveActive {
            lastLoggedKeepAlive = isKeepAliveActive
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
            // 无坐标：信息类，合并，不算错误
            logInfo("电子围栏待就绪", detail: "车辆位置无效，暂未挂载", identity: "geofence-wait-coord")
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

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            enterDegraded(reason: "需要定位权限以启用电子围栏")
            return
        }

        let region = CLCircularRegion(center: centerWGS, radius: radius, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true

        for old in locationManager.monitoredRegions where old.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: old)
        }
        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region)

        monitoredRegion = region
        lastFenceCenter = centerWGS
        lastFenceRadius = radius

        logInfo(
            "电子围栏已更新",
            detail: "半径 \(Int(radius)) 米 · 中心已同步车辆位置",
            identity: "geofence-update|\(Int(radius))"
        )
        CrashLogger.shared.mark("BG", "geofence updated r=\(Int(radius)) lat=\(String(format: "%.5f", centerWGS.latitude)) lng=\(String(format: "%.5f", centerWGS.longitude))")
    }

    private func removeGeofence(reason: String) {
        for old in locationManager.monitoredRegions where old.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: old)
        }
        if monitoredRegion != nil {
            logInfo("电子围栏已移除", detail: reason, identity: "geofence-remove|\(reason)")
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
                logInfo("定位保活已停止", detail: "远离/空闲", identity: "keepalive-stop")
                CrashLogger.shared.mark("BG", "location keep-alive stop")
            }
            return
        }

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            enterDegraded(reason: "定位权限不足，无法开启定位保活")
            return
        }

        locationManager.allowsBackgroundLocationUpdates = (status == .authorizedAlways)
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.startUpdatingLocation()
        if !isKeepAliveActive {
            isKeepAliveActive = true
            let authText = status == .authorizedAlways ? "始终" : "使用期间"
            logInfo("定位保活已开启", detail: "权限=\(authText) · 按需续命", identity: "keepalive-start")
            CrashLogger.shared.mark("BG", "location keep-alive start auth=\(status.rawValue)")
        }
    }

    private func beginBackgroundTask(reason: String) {
        guard settingsStore.settings.backgroundEnhancedEnabled else { return }
        if backgroundTaskID != .invalid { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SGMWKey.\(reason)") { [weak self] in
            self?.logError("后台任务被系统回收", detail: reason, identity: "bg-task-expired")
            self?.endBackgroundTask()
        }
        logInfo("增强后台执行", detail: reasonText(reason), identity: "bg-task-begin|\(reason)")
        CrashLogger.shared.mark("BG", "beginBackgroundTask \(reason) id=\(backgroundTaskID.rawValue)")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        let id = backgroundTaskID
        backgroundTaskID = .invalid
        UIApplication.shared.endBackgroundTask(id)
        logInfo("结束后台任务", detail: "id=\(id.rawValue)", identity: "bg-task-end")
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
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    private func hasSufficientLocationPermission(for settings: KeylessSettings) -> Bool {
        let status = locationManager.authorizationStatus
        if settings.geofenceWakeEnabled || settings.locationKeepAliveEnabled {
            return status == .authorizedAlways || status == .authorizedWhenInUse
        }
        return true
    }

    private func enterDegraded(reason: String) {
        phase = .degraded
        lastLimitationReason = reason
        lastLoggedPhase = .degraded
        postLimitationNotificationIfNeeded(reason: reason)
        logError("后台能力受限", detail: reason, identity: "bg-degraded|\(reason)")
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
        // 进圈/后台续命：允许扫描。ensure 内部会再判「仅围栏内扫描」；
        // 但进圈时 isInGeofence 已 true，不会被抑制。
        store.ensureBLESession(forceRestart: forceRestart, optimisticScanning: true, userInitiated: false)
        logInfo("后台唤醒 BLE", detail: detail, identity: "bg-wake-ble|\(detail)")
    }

    /// 设置变化或出圈后，让 Store 重新评估是否应停扫
    func reapplyBLEScanPolicy(reason: String) {
        guard let store = VehicleStateStoreBridge.current as? MQTTVehicleStateStore else { return }
        store.ensureBLESession(forceRestart: false, optimisticScanning: true, userInitiated: false)
        CrashLogger.shared.mark("BG", "reapply scan policy \(reason) inFence=\(isInGeofence ? 1 : 0)")
    }

    // MARK: - Logging helpers（用户可见 + ×N 合并）

    private func logInfo(_ title: String, detail: String, identity: String, mergeWindow: TimeInterval = 180) {
        eventLog.addCoalesced(
            .system,
            title,
            detail: detail,
            identity: identity,
            mergeWindow: mergeWindow
        )
    }

    private func logError(_ title: String, detail: String, identity: String, mergeWindow: TimeInterval = 300) {
        eventLog.addCoalesced(
            .error,
            title,
            detail: detail,
            identity: identity,
            mergeWindow: mergeWindow
        )
    }

    private func reasonText(_ reason: String) -> String {
        switch reason {
        case "keyless-background": return "锁屏/切后台续命"
        case "approach-arming": return "围栏内警戒"
        case "geofence-enter": return "进入围栏"
        case "location-keepalive": return "定位保活续命"
        case "enter-background": return "进入后台"
        case "enter-foreground": return "回到前台"
        case "settings-change", "settings": return "设置变更"
        case "init": return "启动"
        case "vehicle-location": return "车辆位置更新"
        case "ble-status": return "BLE 状态变化"
        case "enter-region": return "进入围栏"
        case "exit-region": return "离开围栏"
        default: return reason
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        isInGeofence = true
        if settingsStore.settings.backgroundEnhancedEnabled {
            beginBackgroundTask(reason: "geofence-enter")
        }
        requestBLESession(forceRestart: false, detail: "进入电子围栏")
        if let store = VehicleStateStoreBridge.current as? MQTTVehicleStateStore {
            store.applyBackgroundRuntimeSettings(reason: "geofence-enter")
            if store.mqttStatus != .connected {
                store.reconnect()
            }
        }
        reevaluate(reason: "enter-region")
        logInfo("进入电子围栏", detail: "启动蓝牙警戒（不直接解锁）", identity: "geofence-enter")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        isInGeofence = false
        reevaluate(reason: "exit-region")
        // 仅围栏内扫描开启时：出圈停止自动宽扫（已连接会话由 ensure 内部决定保留）
        reapplyBLEScanPolicy(reason: "exit-region")
        logInfo("离开电子围栏", detail: "降低后台活跃度（不自动上锁）", identity: "geofence-exit")
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        switch state {
        case .inside:
            if !isInGeofence {
                isInGeofence = true
                reevaluate(reason: "region-state-inside")
                reapplyBLEScanPolicy(reason: "region-state-inside")
                logInfo("围栏状态", detail: "当前在围栏内", identity: "geofence-state-inside")
            }
        case .outside:
            if isInGeofence {
                isInGeofence = false
                reevaluate(reason: "region-state-outside")
                reapplyBLEScanPolicy(reason: "region-state-outside")
                logInfo("围栏状态", detail: "当前在围栏外", identity: "geofence-state-outside")
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
            logInfo("定位权限", detail: "始终允许", identity: "loc-auth-always")
            updateGeofenceIfNeeded(settings: settings, force: true)
            reevaluate(reason: "auth-always")
        case .authorizedWhenInUse:
            logInfo("定位权限", detail: "使用期间 · 建议改为始终允许以提升后台唤醒", identity: "loc-auth-wheninuse")
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
        // 保活用途：不驱动无感决策，仅维持进程；不写用户日志（太吵）
        if keepAliveDesired, settingsStore.settings.backgroundEnhancedEnabled, !isAppInForeground {
            beginBackgroundTask(reason: "location-keepalive")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 真正错误：定位失败
        logError("定位失败", detail: error.localizedDescription, identity: "loc-fail|\(error.localizedDescription)")
        CrashLogger.shared.mark("BG", "location fail: \(error.localizedDescription)")
    }
}
