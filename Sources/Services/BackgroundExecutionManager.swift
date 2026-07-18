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

    private struct PersistedParkingWake: Codable {
        var latitude: Double
        var longitude: Double
        var radius: Double
        var createdAt: Date
        var wasOutside: Bool
        var source: String
    }

    private struct PersistedPendingConnect: Codable {
        var reason: String
        var createdAt: Date
        var lastStage: String
        var attempts: Int
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
    /// 设置页显示真实定位能力：后台围栏/显著位置变化必须“始终允许”。
    @Published private(set) var locationCapabilityText: String = "定位权限未确定"

    private let locationManager = CLLocationManager()
    private let regionIdentifier = "com.sgmw.key.vehicle.geofence"
    private let parkingRegionIdentifier = "com.sgmw.key.vehicle.parking-fallback"
    private let settingsStore = KeylessSettingsStore.shared
    private let locationDisplayStore = VehicleLocationDisplayStore.shared
    private let connectionStatusStore = VehicleConnectionStatusStore.shared
    private let eventLog = VehicleEventLogStore.shared
    private let persistence = UserDefaults.standard
    private let parkingWakeStoreKey = "BackgroundParkingWake.v1"
    private let pendingConnectStoreKey = "BackgroundPendingConnect.v1"
    private let parkingWakeTTL: TimeInterval = 24 * 60 * 60
    private let pendingConnectTTL: TimeInterval = 15 * 60

    private var cancellables = Set<AnyCancellable>()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// 当前后台任务申请原因（用于到期时分流日志）
    private var backgroundTaskReason: String?
    /// 是否处于系统 expiration 回调路径（避免再刷一条重复的「结束后台任务 id=」）
    private var isEndingBackgroundTaskFromExpiration = false
    private var monitoredRegion: CLCircularRegion?
    private var monitoredParkingRegion: CLCircularRegion?
    private var parkingLocation: CLLocation?
    private var parkingLocationCreatedAt: Date?
    /// 只有先离开停车区域，再重新进入，显著位置变化才触发预唤醒。
    private var parkingFallbackWasOutside = false
    private var parkingLocationSource = "unknown"
    private var pendingConnectStartedAt: Date?
    private var pendingConnectLastStage: String?
    private var pendingConnectReason: String?
    private var pendingConnectAttempts = 0
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
        isAppInForeground = UIApplication.shared.applicationState == .active
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 40
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.allowsBackgroundLocationUpdates = false
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = false
        }

        restorePersistedBackgroundState()
        observeInputs()
        applySettings(settingsStore.settings, reason: "init")
        // 启动时请求一次定位，便于摘要显示距圆心
        if locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestLocation()
        }
        refreshGeofenceSummary()
    }

    // MARK: - Persistence

    private func restorePersistedBackgroundState(now: Date = Date()) {
        updateLocationCapabilityText()

        if let data = persistence.data(forKey: parkingWakeStoreKey),
           let saved = try? JSONDecoder().decode(PersistedParkingWake.self, from: data),
           now.timeIntervalSince(saved.createdAt) <= parkingWakeTTL,
           settingsStore.settings.keylessEnabled,
           settingsStore.settings.parkingFallbackWakeEnabled {
            let location = CLLocation(latitude: saved.latitude, longitude: saved.longitude)
            parkingLocation = location
            parkingLocationCreatedAt = saved.createdAt
            parkingLocationSource = saved.source
            parkingFallbackWasOutside = saved.wasOutside
            let region = CLCircularRegion(
                center: location.coordinate,
                radius: max(100, KeylessSettings.clampedGeofenceRadius(saved.radius)),
                identifier: parkingRegionIdentifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            monitoredParkingRegion = region
            if locationManager.authorizationStatus == .authorizedAlways {
                let alreadyMonitored = locationManager.monitoredRegions.contains { $0.identifier == parkingRegionIdentifier }
                if !alreadyMonitored { locationManager.startMonitoring(for: region) }
                locationManager.startMonitoringSignificantLocationChanges()
            }
            logInfo("停车位置备用状态已恢复", detail: "来源=\(saved.source) · age=\(Int(now.timeIntervalSince(saved.createdAt)))s · 已离开=\(saved.wasOutside ? 1 : 0)", identity: "parking-fallback-restored")
        } else {
            persistence.removeObject(forKey: parkingWakeStoreKey)
            for old in locationManager.monitoredRegions where old.identifier == parkingRegionIdentifier {
                locationManager.stopMonitoring(for: old)
            }
        }

        if let data = persistence.data(forKey: pendingConnectStoreKey),
           let saved = try? JSONDecoder().decode(PersistedPendingConnect.self, from: data),
           now.timeIntervalSince(saved.createdAt) <= pendingConnectTTL,
           settingsStore.settings.keylessEnabled {
            pendingConnectStartedAt = saved.createdAt
            pendingConnectLastStage = saved.lastStage
            pendingConnectReason = saved.reason
            pendingConnectAttempts = saved.attempts
            logInfo("后台待连接已恢复", detail: "\(saved.lastStage) · 原因=\(saved.reason) · 尝试=\(saved.attempts)", identity: "pending-connect-restored")
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingConnectAttempts < 12 else {
                    self?.clearPersistedPendingConnect(reason: "恢复尝试次数已达上限")
                    return
                }
                self.requestBLESession(forceRestart: true, detail: "恢复未完成的后台待连接")
            }
        } else {
            persistence.removeObject(forKey: pendingConnectStoreKey)
        }
    }

    private func persistParkingWake(createdAt: Date? = nil) {
        guard let parkingLocation, let monitoredParkingRegion else { return }
        let value = PersistedParkingWake(
            latitude: parkingLocation.coordinate.latitude,
            longitude: parkingLocation.coordinate.longitude,
            radius: monitoredParkingRegion.radius,
            createdAt: parkingLocationCreatedAt ?? createdAt ?? Date(),
            wasOutside: parkingFallbackWasOutside,
            source: parkingLocationSource
        )
        if let data = try? JSONEncoder().encode(value) {
            persistence.set(data, forKey: parkingWakeStoreKey)
        }
    }

    private func persistPendingConnect() {
        guard let createdAt = pendingConnectStartedAt else {
            persistence.removeObject(forKey: pendingConnectStoreKey)
            return
        }
        let value = PersistedPendingConnect(
            reason: pendingConnectReason ?? "unknown",
            createdAt: createdAt,
            lastStage: pendingConnectLastStage ?? "已创建",
            attempts: pendingConnectAttempts
        )
        if let data = try? JSONEncoder().encode(value) {
            persistence.set(data, forKey: pendingConnectStoreKey)
        }
    }

    private func clearPersistedPendingConnect(reason: String) {
        pendingConnectStartedAt = nil
        pendingConnectLastStage = nil
        pendingConnectReason = nil
        pendingConnectAttempts = 0
        persistence.removeObject(forKey: pendingConnectStoreKey)
        logInfo("后台待连接已清理", detail: reason, identity: "pending-connect-clear|\(reason)", mergeWindow: 30)
    }

    private func updateLocationCapabilityText() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            locationCapabilityText = "始终允许 · 后台围栏/显著位置可用"
        case .authorizedWhenInUse:
            locationCapabilityText = "使用期间 · 前台定位可用，后台围栏受限"
        case .denied:
            locationCapabilityText = "已拒绝 · 后台定位不可用"
        case .restricted:
            locationCapabilityText = "系统限制 · 后台定位不可用"
        case .notDetermined:
            locationCapabilityText = "未授权 · 需要始终允许"
        @unknown default:
            locationCapabilityText = "未知权限状态"
        }
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
        configureParkingFallbackIfNeeded(settings: settings, reason: "enter-background")
        reevaluate(reason: "enter-background")
        if settings.keylessEnabled {
            // 未鉴权时 forceRestart，避免卡在半连接/空闲却不扫
            let force = connectionStatusStore.bleStatus != .authenticated
            requestBLESession(forceRestart: force, detail: "进入后台")
        }
    }

    func handleWillEnterForeground() {
        isAppInForeground = true
        // 本轮停车备用点生命周期结束；下次进入后台重新固定最新停车位置。
        removeParkingFallback(reason: "回到前台，等待下次停车")
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
        configureParkingFallbackIfNeeded(settings: settings, reason: reason)
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
            .sink { [weak self] status in
                self?.recordPendingConnectStage(status)
                self?.notifyBLEStatusChanged()
            }
            .store(in: &cancellables)
    }

    private func recordPendingConnectStage(_ status: VehicleConnectionStatusStore.LiveBLEStatus) {
        guard let started = pendingConnectStartedAt else { return }
        let stage: String
        switch status {
        case .scanning: stage = "扫描中"
        case .connecting: stage = "连接中"
        case .connected, .authenticating: stage = "安全重鉴权中"
        case .authenticated: stage = "已鉴权"
        case .error: stage = "失败"
        case .pausedOutsideFence: stage = "围栏外休眠"
        case .disconnected: stage = "等待系统机会"
        }
        guard stage != pendingConnectLastStage else { return }
        pendingConnectLastStage = stage
        persistPendingConnect()
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))
        logInfo("后台待连接", detail: "\(stage) · 已用时 \(elapsed)", identity: "pending-connect|\(stage)", mergeWindow: 30)
        if status == .authenticated {
            clearPersistedPendingConnect(reason: "BLE 已完成安全鉴权")
        } else if status == .error {
            pendingConnectLastStage = "失败，等待系统机会"
            persistPendingConnect()
        }
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

        // 权限不足 → 受限（后台围栏/停车备用/定位保活都需要 Always）
        if (settings.geofenceWakeEnabled || settings.parkingFallbackWakeEnabled || settings.locationKeepAliveEnabled),
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
        // 挂载后主动问一次系统圈内外；同时 refresh 已用距离校正兜底
        locationManager.requestState(for: region)

        let distText: String
        if let d = distanceToFenceCenterMeters {
            distText = d < 1000 ? String(format: "距圆心约 %.0f 米", d) : String(format: "距圆心约 %.1f 公里", d / 1000)
        } else {
            distText = "距圆心--"
        }
        let zoneText = isInGeofence ? "圈内" : "圈外"
        logInfo(
            "电子围栏已更新",
            detail: "半径 \(Int(radius)) 米 · \(distText) · \(zoneText)" + (geofenceCenterAddress.isEmpty ? "" : " · \(geofenceCenterAddress)"),
            identity: "geofence-update|\(Int(radius))"
        )
        // 围栏更新已写事件日志，不重复进错误日志
    }

    /// 默认关闭的停车位备用策略：进后台时以手机当前位置挂一个小围栏，并启动显著位置变化。
    /// 仅预唤醒 BLE，不参与任何锁/解锁判断。
    private func configureParkingFallbackIfNeeded(settings: KeylessSettings, reason: String) {
        guard settings.keylessEnabled, settings.parkingFallbackWakeEnabled else {
            removeParkingFallback(reason: "开关关闭")
            return
        }
        guard locationManager.authorizationStatus == .authorizedAlways else {
            enterDegraded(reason: "停车位置备用唤醒需要“始终允许”定位")
            return
        }
        guard !isAppInForeground else { return }
        // 圆心优先使用车辆位置；仅车辆位置不可用且手机已在车旁完成 BLE 鉴权时，才用手机当前位置。
        let vehicleLocation = currentVehicleCoordinateWGS84().map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let authenticatedNearVehicle = connectionStatusStore.bleStatus == .authenticated
        let location = vehicleLocation ?? (authenticatedNearVehicle ? (lastPhoneLocation ?? locationManager.location) : nil)
        guard let location else {
            locationManager.requestLocation()
            logInfo("停车位置待记录", detail: "车辆位置不可用，等待车旁 BLE 鉴权后采用手机位置", identity: "parking-wait")
            return
        }
        // 一次后台会话只固定一个停车点，不随手机定位移动。
        if monitoredParkingRegion != nil { return }
        let radius = max(100, KeylessSettings.clampedGeofenceRadius(settings.geofenceRadiusMeters))
        let region = CLCircularRegion(center: location.coordinate, radius: radius, identifier: parkingRegionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
        locationManager.startMonitoringSignificantLocationChanges()
        monitoredParkingRegion = region
        parkingLocation = location
        parkingLocationCreatedAt = Date()
        parkingLocationSource = vehicleLocation != nil ? "vehicle-http" : "phone-ble-auth"
        parkingFallbackWasOutside = false
        persistParkingWake()
        logInfo("停车位置备用唤醒已就绪", detail: "半径 \(Int(radius)) 米 · 来源=\(parkingLocationSource) · 显著位置变化已监听 · \(reasonText(reason))", identity: "parking-fallback-ready")
    }

    private func removeParkingFallback(reason: String) {
        for old in locationManager.monitoredRegions where old.identifier == parkingRegionIdentifier { locationManager.stopMonitoring(for: old) }
        if monitoredParkingRegion != nil { logInfo("停车位置备用唤醒已移除", detail: reason, identity: "parking-fallback-remove") }
        monitoredParkingRegion = nil
        parkingLocation = nil
        parkingLocationCreatedAt = nil
        parkingLocationSource = "unknown"
        parkingFallbackWasOutside = false
        persistence.removeObject(forKey: parkingWakeStoreKey)
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    private func wakeFromParkingFallback(_ detail: String) {
        guard settingsStore.settings.keylessEnabled, settingsStore.settings.parkingFallbackWakeEnabled else { return }
        if settingsStore.settings.backgroundEnhancedEnabled { beginBackgroundTask(reason: "parking-fallback") }
        pendingConnectStartedAt = Date()
        requestBLESession(forceRestart: false, detail: detail)
        logInfo("停车位置预唤醒", detail: "\(detail) · 仅启动扫描/鉴权，不直接控车", identity: "parking-fallback-wake")
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

        // 核心修复：CLRegion 回调常滞后/漏报。距圆心已明确在半径内却仍标「圈外」→ 误开「仅围栏内扫描」休眠。
        // 用直线距离校正 isInGeofence（进出带一点滞回，避免边界抖）。
        if let d = distanceToFenceCenterMeters {
            let radius = lastFenceRadius > 0
                ? lastFenceRadius
                : KeylessSettings.clampedGeofenceRadius(settings.geofenceRadiusMeters)
            let enterR = radius
            let exitR = radius * 1.08 + 8 // 略放宽离开，减少边界来回
            let wasIn = isInGeofence
            if !wasIn, d <= enterR {
                isInGeofence = true
                logInfo(
                    "围栏状态",
                    detail: "距离校正为圈内 · 距圆心约 \(Int(d)) 米 / 半径 \(Int(radius)) 米",
                    identity: "geofence-distance-inside",
                    mergeWindow: 30
                )
                reevaluate(reason: "distance-inside")
                reapplyBLEScanPolicy(reason: "distance-inside")
                if settings.keylessEnabled {
                    requestBLESession(forceRestart: false, detail: "距离校正进圈")
                }
            } else if wasIn, d > exitR {
                isInGeofence = false
                logInfo(
                    "围栏状态",
                    detail: "距离校正为圈外 · 距圆心约 \(Int(d)) 米 / 半径 \(Int(radius)) 米",
                    identity: "geofence-distance-outside",
                    mergeWindow: 30
                )
                reevaluate(reason: "distance-outside")
                reapplyBLEScanPolicy(reason: "distance-outside")
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
        // 已有有效任务时：只更新 reason，不重复 begin（iOS 不支持真正延长同一 ID）
        if backgroundTaskID != .invalid {
            backgroundTaskReason = reason
            return
        }
        backgroundTaskReason = reason
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SGMWKey.\(reason)") { [weak self] in
            self?.handleBackgroundTaskExpired()
        }
        // 系统若立刻返回 invalid，不要当成成功
        if backgroundTaskID == .invalid {
            backgroundTaskReason = nil
            logInfo("增强后台执行失败", detail: "系统未批准 · \(reasonText(reason))", identity: "bg-task-denied|\(reason)", mergeWindow: 60)
            return
        }
        logInfo("增强后台执行", detail: reasonText(reason), identity: "bg-task-begin|\(reason)")
        // 开始后台任务已写事件日志；错误日志只记异常到期
    }

    /// 系统回收短时后台任务：
    /// - 圈外/围栏休眠等省电路径 → 系统信息（正常挂起，不标错误）
    /// - 圈内警戒 / BLE 活跃 / 鉴权中 → 仍记错误（真异常）
    /// - 若仍需无感：立刻申请下一段短时任务并接力 BLE（日志里「等待系统机会」常因到期后没人再推一把）
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

        // 接力：鉴权中/圈内/还在连 → 再申请一段窗口，避免锁屏走几步进程就冻住
        relayBackgroundWorkIfNeeded(trigger: "task-expired|\(reason)")
    }

    /// 后台仍需要无感时，再开一段 background task，并在未鉴权时推 BLE 重连。
    private func relayBackgroundWorkIfNeeded(trigger: String) {
        guard !isAppInForeground else { return }
        let settings = settingsStore.settings
        guard settings.keylessEnabled, settings.backgroundEnhancedEnabled else { return }

        let auth = connectionStatusStore.bleStatus == .authenticated
        let busy = isBLEBusy
        // 圈内，或 BLE 还在忙/已鉴权，或仍有未完成的待连接 → 值得再续一段
        let shouldRelay =
            isInGeofence
            || auth
            || busy
            || pendingConnectStartedAt != nil
            || keepAliveDesired

        guard shouldRelay else { return }

        beginBackgroundTask(reason: "keyless-relay")
        logInfo(
            "后台无感接力",
            detail: "\(trigger) · phase=\(phase.rawValue) · fence=\(isInGeofence ? 1 : 0) · ble=\(bleStatusText(connectionStatusStore.bleStatus))",
            identity: "bg-keyless-relay|\(trigger)",
            mergeWindow: 20
        )

        if auth {
            // 已鉴权：只续命，让 RSSI/无感判定继续跑
            return
        }
        // 未鉴权：强制推一把扫描/连接（比 enter-background 的 forceRestart:false 更积极）
        requestBLESession(forceRestart: true, detail: "后台接力·\(trigger)")
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
        removeParkingFallback(reason: reason)
        setKeepAliveActive(false)
        endBackgroundTask()
        isInGeofence = false
        // stopAll 用户可见路径已有事件；不刷错误日志
    }

    // MARK: - Permission / degraded

    private func requestAuthorizationIfNeeded(for settings: KeylessSettings) {
        let status = locationManager.authorizationStatus
        let needsBackgroundLocation = settings.geofenceWakeEnabled || settings.parkingFallbackWakeEnabled || settings.locationKeepAliveEnabled
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
        if settings.geofenceWakeEnabled || settings.parkingFallbackWakeEnabled || settings.locationKeepAliveEnabled {
            return status == .authorizedAlways
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
            body: reason,
            source: "background"
        )
    }

    private func requestBLESession(forceRestart: Bool, detail: String) {
        guard let store = VehicleStateStoreBridge.current as? MQTTVehicleStateStore else { return }
        if connectionStatusStore.bleStatus == .authenticated {
            if pendingConnectStartedAt != nil {
                clearPersistedPendingConnect(reason: "BLE 已处于鉴权完成状态")
            }
            return
        }
        // 进圈/后台续命：允许扫描。ensure 内部会再判「仅围栏内扫描」；
        // 但进圈时 isInGeofence 已 true，不会被抑制。
        if pendingConnectStartedAt == nil {
            pendingConnectStartedAt = Date()
            pendingConnectLastStage = "已创建"
            pendingConnectReason = detail
            pendingConnectAttempts = 1
            logInfo("后台待连接", detail: "已创建 · 原因：\(detail)", identity: "pending-connect|created", mergeWindow: 30)
        } else if pendingConnectLastStage == "失败，等待系统机会" || pendingConnectLastStage == "等待系统机会" {
            pendingConnectAttempts += 1
            pendingConnectLastStage = "已创建"
            pendingConnectReason = detail
        } else {
            // 同一轮扫描/连接中的重复唤醒只更新原因，不重复计次。
            pendingConnectReason = detail
        }
        // 后台断连/连不上时需要多试几次；日志里 5 次很快耗尽后只剩「等待系统机会」
        if pendingConnectAttempts > 12 {
            clearPersistedPendingConnect(reason: "后台接力尝试次数已达上限")
            return
        }
        persistPendingConnect()
        store.ensureBLESession(forceRestart: forceRestart, optimisticScanning: true, userInitiated: false)
        logInfo("后台唤醒 BLE", detail: "\(detail) · 等待扫描/连接/重鉴权 · 尝试\(pendingConnectAttempts)", identity: "bg-wake-ble|\(detail)")
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

    private func bleStatusText(_ status: VehicleConnectionStatusStore.LiveBLEStatus) -> String {
        switch status {
        case .disconnected: return "未连接"
        case .scanning: return "扫描中"
        case .pausedOutsideFence: return "围栏外休眠"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .authenticating: return "鉴权中"
        case .authenticated: return "已鉴权"
        case .error: return "错误"
        }
    }

    private func reasonText(_ reason: String) -> String {
        switch reason {
        case "keyless-background": return "锁屏/切后台续命"
        case "keyless-relay": return "无感后台接力续命"
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
        case "parking-fallback": return "停车位置备用唤醒"
        default: return reason
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if region.identifier == parkingRegionIdentifier {
            guard parkingFallbackWasOutside else {
                logInfo("停车位置预唤醒跳过", detail: "尚未确认离开停车区域", identity: "parking-fallback-no-exit")
                return
            }
            parkingFallbackWasOutside = false
            persistParkingWake()
            wakeFromParkingFallback("离开后重新进入停车位置备用围栏")
            return
        }
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
        if region.identifier == parkingRegionIdentifier {
            parkingFallbackWasOutside = true
            persistParkingWake()
            logInfo("离开停车位置备用围栏", detail: "已武装下次重新进入预唤醒", identity: "parking-fallback-exit")
            return
        }
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
        updateLocationCapabilityText()
        let settings = settingsStore.settings
        switch manager.authorizationStatus {
        case .authorizedAlways:
            logInfo("定位权限", detail: "始终允许", identity: "loc-auth-always")
            updateGeofenceIfNeeded(settings: settings, force: true)
            reevaluate(reason: "auth-always")
        case .authorizedWhenInUse:
            logInfo("定位权限", detail: "使用期间 · 建议改为始终允许以提升后台唤醒", identity: "loc-auth-wheninuse")
            if settings.geofenceWakeEnabled || settings.parkingFallbackWakeEnabled || settings.locationKeepAliveEnabled {
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
            let previousPhone = lastPhoneLocation
            lastPhoneLocation = last
            if !isAppInForeground, monitoredParkingRegion == nil {
                configureParkingFallbackIfNeeded(settings: settingsStore.settings, reason: "location-update")
            }
            if let parking = parkingLocation, !isAppInForeground {
                let distance = last.distance(from: parking)
                let previousDistance = previousPhone?.distance(from: parking)
                if distance > 120, !parkingFallbackWasOutside {
                    parkingFallbackWasOutside = true
                    persistParkingWake()
                }
                // 显著位置回调只有“由远到近”才预唤醒；远离时只武装，不唤醒。
                if parkingFallbackWasOutside, distance <= 120, (previousDistance ?? .greatestFiniteMagnitude) > 120 {
                    parkingFallbackWasOutside = false
                    persistParkingWake()
                    wakeFromParkingFallback("显著位置变化由远到近，距停车点约 \(Int(distance)) 米")
                }
            }
            // 更新手机距圆心，方便 UI 校验围栏（无新鲜度字段）
            refreshGeofenceSummary()
        }
        // 保活用途：维持进程；同时若无感未鉴权且在圈内，顺手再推 BLE（显著位置/定位回调是后台少数窗口）
        if keepAliveDesired, settingsStore.settings.backgroundEnhancedEnabled, !isAppInForeground {
            beginBackgroundTask(reason: "location-keepalive")
            if settingsStore.settings.keylessEnabled,
               connectionStatusStore.bleStatus != .authenticated,
               isInGeofence || isBLEBusy || pendingConnectStartedAt != nil {
                requestBLESession(forceRestart: false, detail: "定位保活窗口")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 真正错误：定位失败
        logError("定位失败", detail: error.localizedDescription, identity: "loc-fail|\(error.localizedDescription)")
        CrashLogger.shared.mark("BG", "location fail: \(error.localizedDescription)")
    }
}
