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
    /// 围栏数据行：半径 · 距圆心（无感 A+C 用，不含圈内外/地址）
    @Published private(set) var geofenceMetricsText: String = "围栏未挂载"
    /// 设置页数据行：半径 · 距圆心 · 圈内/外
    @Published private(set) var geofenceSettingsMetricsText: String = "围栏未挂载"
    /// 兼容旧字段：等同 settings 数据行（日志/旧 UI）
    @Published private(set) var geofenceSummaryText: String = "围栏未挂载"
    /// 圆心地址；空则 UI 隐藏地址行
    @Published private(set) var geofenceCenterAddress: String = ""
    @Published private(set) var distanceToFenceCenterMeters: CLLocationDistance?

    private let locationManager = CLLocationManager()
    private let regionIdentifier = "com.sgmw.key.vehicle.geofence"
    private let settingsStore = KeylessSettingsStore.shared
    private let locationDisplayStore = VehicleLocationDisplayStore.shared
    private let connectionStatusStore = VehicleConnectionStatusStore.shared
    private let eventLog = VehicleEventLogStore.shared

    private var cancellables = Set<AnyCancellable>()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// 当前后台任务申请原因（用于到期时分流日志）
    private var backgroundTaskReason: String?
    /// 是否处于系统 expiration 回调路径（避免再刷一条重复的「结束后台任务 id=」）
    private var isEndingBackgroundTaskFromExpiration = false
    private var monitoredRegion: CLCircularRegion?
    private var lastFenceCenter: CLLocationCoordinate2D?
    private var lastFenceRadius: CLLocationDistance = 0
    private var lastPhoneLocation: CLLocation?
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
        // 启动时请求一次定位，便于摘要显示距圆心
        if locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestLocation()
        }
        refreshGeofenceSummary()
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

        // 地址变化时只刷摘要，不重挂围栏
        locationDisplayStore.$liveAddress
            .combineLatest(locationDisplayStore.$cachedAddress)
            .receive(on: DispatchQueue.main)
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshGeofenceSummary()
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

        // 例行 reeval 不写错误日志（用户可见阶段/围栏已在事件日志）
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
            // 圆心半径未变，仍刷新摘要（手机距离/地址可能变）
            refreshGeofenceSummary()
            return
        }

        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            enterDegraded(reason: "需要定位权限以启用电子围栏")
            refreshGeofenceSummary()
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

        // 同步地址（与雷达同一套车坐标/地址，不含新鲜度）
        geofenceCenterAddress = locationDisplayStore.displayAddress
        refreshGeofenceSummary()

        let distText: String
        if let d = distanceToFenceCenterMeters {
            distText = d < 1000 ? String(format: "距圆心约 %.0f 米", d) : String(format: "距圆心约 %.1f 公里", d / 1000)
        } else {
            distText = "距圆心--"
        }
        logInfo(
            "电子围栏已更新",
            detail: "半径 \(Int(radius)) 米 · \(distText)" + (geofenceCenterAddress.isEmpty ? "" : " · \(geofenceCenterAddress)"),
            identity: "geofence-update|\(Int(radius))"
        )
        // 围栏更新已写事件日志，不重复进错误日志
    }

    private func removeGeofence(reason: String) {
        for old in locationManager.monitoredRegions where old.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: old)
        }
        if monitoredRegion != nil {
            logInfo("电子围栏已移除", detail: reason, identity: "geofence-remove|\(reason)")
            // 围栏移除已写事件日志
        }
        monitoredRegion = nil
        lastFenceCenter = nil
        lastFenceRadius = 0
        if isInGeofence {
            isInGeofence = false
        }
        refreshGeofenceSummary()
    }

    private func currentVehicleCoordinateWGS84() -> CLLocationCoordinate2D? {
        let latGcj = locationDisplayStore.displayLatitudeGcj
        let lngGcj = locationDisplayStore.displayLongitudeGcj
        guard latGcj != 0, lngGcj != 0 else { return nil }
        let wgs = LocationResolver.gcj02ToWgs84(lat: latGcj, lng: lngGcj)
        guard abs(wgs.lat) <= 90, abs(wgs.lng) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: wgs.lat, longitude: wgs.lng)
    }

    /// 刷新围栏摘要：数据行与地址分离（无新鲜度）
    private func refreshGeofenceSummary() {
        let settings = settingsStore.settings
        let address = locationDisplayStore.displayAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        geofenceCenterAddress = address

        func applyIdle(_ text: String) {
            distanceToFenceCenterMeters = nil
            geofenceMetricsText = text
            geofenceSettingsMetricsText = text
            geofenceSummaryText = text
        }

        if !settings.keylessEnabled {
            applyIdle("随无感停用")
            return
        }
        if !settings.geofenceWakeEnabled {
            applyIdle("围栏未开启")
            return
        }
        guard let center = lastFenceCenter ?? currentVehicleCoordinateWGS84() else {
            applyIdle("待就绪 · 无车辆坐标")
            return
        }
        let radius = Int(lastFenceRadius > 0 ? lastFenceRadius : KeylessSettings.clampedGeofenceRadius(settings.geofenceRadiusMeters))

        // 手机距圆心（WGS 直线距离）
        if let phone = lastPhoneLocation ?? locationManager.location {
            lastPhoneLocation = phone
            let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            distanceToFenceCenterMeters = phone.distance(from: centerLoc)
        } else {
            distanceToFenceCenterMeters = nil
            // 无手机点时补一次定位（不开启持续保活）
            let auth = locationManager.authorizationStatus
            if auth == .authorizedAlways || auth == .authorizedWhenInUse {
                locationManager.requestLocation()
            }
        }

        let distPart: String
        if let d = distanceToFenceCenterMeters {
            if d < 1000 {
                distPart = String(format: "距圆心约 %.0f 米", d)
            } else {
                distPart = String(format: "距圆心约 %.1f 公里", d / 1000)
            }
        } else {
            distPart = "距圆心--"
        }
        let zonePart = isInGeofence ? "圈内" : "圈外"

        // 无感 A+C：仅 半径 · 距圆心（圈内外由「围栏状态」表达）
        geofenceMetricsText = "半径 \(radius) 米 · \(distPart)"
        // 设置两行：数据行含圈内外，地址另起一行
        geofenceSettingsMetricsText = "半径 \(radius) 米 · \(distPart) · \(zonePart)"
        // 兼容旧字段（日志等）
        if address.isEmpty {
            geofenceSummaryText = geofenceSettingsMetricsText
        } else {
            geofenceSummaryText = "\(geofenceSettingsMetricsText) · \(address)"
        }
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
                // 保活停止已写事件日志
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
            // 保活开启已写事件日志
        }
    }

    private func beginBackgroundTask(reason: String) {
        guard settingsStore.settings.backgroundEnhancedEnabled else { return }
        if backgroundTaskID != .invalid { return }
        backgroundTaskReason = reason
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SGMWKey.\(reason)") { [weak self] in
            self?.handleBackgroundTaskExpired()
        }
        logInfo("增强后台执行", detail: reasonText(reason), identity: "bg-task-begin|\(reason)")
        // 开始后台任务已写事件日志；错误日志只记异常到期
    }

    /// 系统回收短时后台任务：
    /// - 圈外/围栏休眠等省电路径 → 系统信息（正常挂起，不标错误）
    /// - 圈内警戒 / BLE 活跃 / 鉴权中 → 仍记错误（真异常）
    private func handleBackgroundTaskExpired() {
        let reason = backgroundTaskReason ?? "unknown"
        let detailPrefix = expirationDetail(for: reason)
        if shouldTreatBackgroundExpirationAsError {
            logError(
                "后台任务被系统回收",
                detail: "\(detailPrefix) · \(reason)",
                identity: "bg-task-expired-error|\(reason)|\(phase.rawValue)"
            )
        } else {
            logInfo(
                "短时任务结束",
                detail: "\(detailPrefix) · \(reason)",
                identity: "bg-task-expired-normal|\(reason)|\(phase.rawValue)"
            )
        }
        // 正常挂起不写错误日志；异常到期上面已 logError，必要时再 mark
        if shouldTreatBackgroundExpirationAsError {
            CrashLogger.shared.mark(
                "BG",
                "backgroundTask expired reason=\(reason) phase=\(phase.rawValue) fence=\(isInGeofence ? 1 : 0)"
            )
        }
        isEndingBackgroundTaskFromExpiration = true
        endBackgroundTask()
        isEndingBackgroundTaskFromExpiration = false
    }

    /// 仅在「确实在干活」时把到期标错误：保活中 / 圈内警戒 / BLE 活跃 / 鉴权中。
    /// 圈外休眠、无感关闭、兜底 phase 不算错误。
    private var shouldTreatBackgroundExpirationAsError: Bool {
        if isKeepAliveActive || keepAliveDesired { return true }
        if isInGeofence { return true }
        switch phase {
        case .bleActive, .keylessAuthenticated:
            return true
        case .approachArming:
            // 只有真在圈内警戒才算；圈外被兜底成 approachArming 不算
            return isInGeofence
        case .fenceSleep, .idleDisabled, .degraded:
            return false
        }
    }

    private func expirationDetail(for reason: String) -> String {
        if shouldTreatBackgroundExpirationAsError {
            if isKeepAliveActive || keepAliveDesired {
                return "定位保活中被中断"
            }
            if isInGeofence || phase == .approachArming {
                return "围栏内警戒中被中断"
            }
            switch phase {
            case .bleActive:
                return "BLE 活跃中被中断"
            case .keylessAuthenticated:
                return "鉴权中被中断"
            default:
                return "后台执行中被中断 · \(phase.rawValue)"
            }
        }
        // 正常挂起：详细说明当前为何不值得标错误
        if phase == .fenceSleep || (!isInGeofence && settingsStore.settings.scanOnlyInsideGeofence) {
            return "围栏外休眠 · 正常挂起"
        }
        if !settingsStore.settings.keylessEnabled {
            return "无感已关 · 正常挂起"
        }
        if !isInGeofence {
            return "围栏外 · 正常挂起 · \(phase.rawValue)"
        }
        return "正常挂起 · \(phase.rawValue)"
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        let id = backgroundTaskID
        backgroundTaskID = .invalid
        backgroundTaskReason = nil
        UIApplication.shared.endBackgroundTask(id)
        // 到期路径已写「短时任务结束 / 被系统回收」，避免再刷一条重复 id 日志
        if !isEndingBackgroundTaskFromExpiration {
            logInfo("结束后台任务", detail: "id=\(id.rawValue)", identity: "bg-task-end")
        }
        // 例行 end 不写错误日志
    }

    private func stopAll(reason: String) {
        removeGeofence(reason: reason)
        setKeepAliveActive(false)
        endBackgroundTask()
        isInGeofence = false
        // stopAll 用户可见路径已有事件；不刷错误日志
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
        // 扫描策略重评估不写错误日志
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
            if settingsStore.settings.mqttEnabled, store.mqttStatus != .connected {
                store.reconnect()
            }
        }
        reevaluate(reason: "enter-region")
        refreshGeofenceSummary()
        logInfo("进入电子围栏", detail: "启动蓝牙警戒（不直接解锁）", identity: "geofence-enter")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        isInGeofence = false
        reevaluate(reason: "exit-region")
        // 仅围栏内扫描开启时：出圈停止自动宽扫（已连接会话由 ensure 内部决定保留）
        reapplyBLEScanPolicy(reason: "exit-region")
        refreshGeofenceSummary()
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
                refreshGeofenceSummary()
                logInfo("围栏状态", detail: "当前在围栏内", identity: "geofence-state-inside")
            } else {
                refreshGeofenceSummary()
            }
        case .outside:
            if isInGeofence {
                isInGeofence = false
                reevaluate(reason: "region-state-outside")
                reapplyBLEScanPolicy(reason: "region-state-outside")
                refreshGeofenceSummary()
                logInfo("围栏状态", detail: "当前在围栏外", identity: "geofence-state-outside")
            } else {
                refreshGeofenceSummary()
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
        if let last = locations.last {
            lastPhoneLocation = last
            // 更新手机距圆心，方便 UI 校验围栏（无新鲜度字段）
            refreshGeofenceSummary()
        }
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
