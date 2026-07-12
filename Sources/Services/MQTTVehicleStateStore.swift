import Foundation
import UIKit
import Combine
import CocoaMQTT

struct VehicleControlMQTTResult: Equatable, Identifiable {
    let id = UUID()
    let resultCode: String
    let message: String
    let serviceCode: String
    let timestampMillis: Int64?
    let receivedAt: Date

    var isSuccess: Bool {
        let normalized = resultCode.lowercased()
        return normalized == "0" || normalized == "1" || normalized == "true" || normalized == "success"
    }

    var displayDetail: String {
        let codeText = resultCode.isEmpty ? "--" : resultCode
        let serviceText = serviceCode.isEmpty ? "--" : serviceCode
        let messageText = message.isEmpty ? "--" : message
        return "serviceCode=\(serviceText), resultCode=\(codeText), message=\(messageText)"
    }
}

// MARK: - MQTT + HTTP 车辆状态 Store
// 双通道：
// - HTTP：电量/续航/位置/档位/温度等基础状态（稳定兜底）
// - MQTT：门锁/车窗/空调/控制结果等实时变化
// - 控制：快捷操作 lock / unlock 进入 HTTP 试接，其它命令和无感暂不接真实执行

final class MQTTVehicleStateStore: VehicleStateStore {

    struct VehicleTokenSource: Equatable {
        let label: String
        let path: String

        var displayText: String {
            path.isEmpty ? label : "\(label) · \(path)"
        }
    }

    // MARK: - 连接状态

    typealias LiveBLEStatus = VehicleConnectionStatusStore.LiveBLEStatus
    typealias LiveMQTTStatus = VehicleConnectionStatusStore.LiveMQTTStatus

    let connectionStatusStore = VehicleConnectionStatusStore.shared
    let bleKeyInfoStore = VehicleBLEKeyInfoStore.shared
    let locationDisplayStore = VehicleLocationDisplayStore.shared
    let controlFeedbackStore = VehicleControlFeedbackStore.shared

    var bleStatus: LiveBLEStatus {
        get { connectionStatusStore.bleStatus }
        set { connectionStatusStore.bleStatus = newValue }
    }
    var mqttStatus: LiveMQTTStatus {
        get { connectionStatusStore.mqttStatus }
        set { connectionStatusStore.mqttStatus = newValue }
    }
    var authStatus: StatusAuthState {
        get { connectionStatusStore.authStatus }
        set { connectionStatusStore.authStatus = newValue }
    }
    var latestBleKeyInfo: [String: String] {
        get { bleKeyInfoStore.latestBleKeyInfo }
        set { bleKeyInfoStore.latestBleKeyInfo = newValue }
    }
    let tokenSourceStore = VehicleTokenSourceStore.shared
    var tokenSourcePath: String {
        get { tokenSourceStore.path }
        set { tokenSourceStore.path = newValue }
    }
    var tokenSourceLabel: String {
        get { tokenSourceStore.label }
        set { tokenSourceStore.label = newValue }
    }

    var cachedLatitudeGcj: Double {
        get { locationDisplayStore.cachedLatitudeGcj }
        set { locationDisplayStore.cachedLatitudeGcj = newValue }
    }
    var cachedLongitudeGcj: Double {
        get { locationDisplayStore.cachedLongitudeGcj }
        set { locationDisplayStore.cachedLongitudeGcj = newValue }
    }
    var cachedAddress: String {
        get { locationDisplayStore.cachedAddress }
        set { locationDisplayStore.cachedAddress = newValue }
    }
    var liveLatitudeGcj: Double {
        get { locationDisplayStore.liveLatitudeGcj }
        set { locationDisplayStore.liveLatitudeGcj = newValue }
    }
    var liveLongitudeGcj: Double {
        get { locationDisplayStore.liveLongitudeGcj }
        set { locationDisplayStore.liveLongitudeGcj = newValue }
    }
    var liveAddress: String {
        get { locationDisplayStore.liveAddress }
        set { locationDisplayStore.liveAddress = newValue }
    }
    var latestBLEControlReceipt: VehicleBLEManager.BLEControlReceipt? {
        get { controlFeedbackStore.latestBLEControlReceipt }
        set { controlFeedbackStore.latestBLEControlReceipt = newValue }
    }
    var latestControlResult: VehicleControlMQTTResult? {
        get { controlFeedbackStore.latestControlResult }
        set { controlFeedbackStore.latestControlResult = newValue }
    }

    var displayLatitudeGcj: Double { locationDisplayStore.displayLatitudeGcj }
    var displayLongitudeGcj: Double { locationDisplayStore.displayLongitudeGcj }
    var displayAddress: String { locationDisplayStore.displayAddress }

    var debugBLERawRSSI: Int? {
        get { bleDiagnosticsStore.debugRawRSSI }
        set { bleDiagnosticsStore.debugRawRSSI = newValue }
    }
    var debugBLESmoothedRSSI: Int? {
        get { bleDiagnosticsStore.debugSmoothedRSSI }
        set { bleDiagnosticsStore.debugSmoothedRSSI = newValue }
    }
    var debugBLELastSeenText: String {
        get { bleDiagnosticsStore.debugLastSeenText }
        set { bleDiagnosticsStore.debugLastSeenText = newValue }
    }
    var debugBLELastTransitionText: String {
        get { bleDiagnosticsStore.debugLastTransitionText }
        set { bleDiagnosticsStore.debugLastTransitionText = newValue }
    }
    var bleDiagnosticPhaseText: String {
        get { bleDiagnosticsStore.phaseText }
        set { bleDiagnosticsStore.phaseText = newValue }
    }
    var bleDiagnosticDetailText: String {
        get { bleDiagnosticsStore.detailText }
        set { bleDiagnosticsStore.detailText = newValue }
    }
    var bleDiagnosticLastConclusionText: String {
        get { bleDiagnosticsStore.lastConclusionText }
        set { bleDiagnosticsStore.lastConclusionText = newValue }
    }
    var bleDiagnosticLastConclusionAtText: String {
        get { bleDiagnosticsStore.lastConclusionAtText }
        set { bleDiagnosticsStore.lastConclusionAtText = newValue }
    }
    var bleDiagnosticLastReasonText: String {
        get { bleDiagnosticsStore.lastReasonText }
        set { bleDiagnosticsStore.lastReasonText = newValue }
    }
    var bleDiagnosticNoDeviceCount: Int {
        get { bleDiagnosticsStore.noDeviceCount }
        set { bleDiagnosticsStore.noDeviceCount = newValue }
    }
    var bleDiagnosticFoundButNotConnectedCount: Int {
        get { bleDiagnosticsStore.foundButNotConnectedCount }
        set { bleDiagnosticsStore.foundButNotConnectedCount = newValue }
    }
    var bleDiagnosticAuthFailedCount: Int {
        get { bleDiagnosticsStore.authFailedCount }
        set { bleDiagnosticsStore.authFailedCount = newValue }
    }
    var bleDidSeeDeviceThisCycle: Bool {
        get { bleDiagnosticsStore.didSeeDeviceThisCycle }
        set { bleDiagnosticsStore.didSeeDeviceThisCycle = newValue }
    }
    var bleDidReachConnectedThisCycle: Bool {
        get { bleDiagnosticsStore.didReachConnectedThisCycle }
        set { bleDiagnosticsStore.didReachConnectedThisCycle = newValue }
    }
    var bleCurrentCandidateName: String {
        get { bleDiagnosticsStore.currentCandidateName }
        set { bleDiagnosticsStore.currentCandidateName = newValue }
    }
    var bleCurrentCandidateRSSI: Int? {
        get { bleDiagnosticsStore.currentCandidateRSSI }
        set { bleDiagnosticsStore.currentCandidateRSSI = newValue }
    }

    var mqtt: CocoaMQTT?
    var credentials: SGMWApiClient.MQTTCredentials?
    var credentialsStore: VehicleCredentialsStore

    var lastMqttFields: [String: String] = [:]
    /// 当前车身模型权威 collectTime（官方 setCarStatusModel 同款）
    var bodyCollectTime: Date?
    /// 字段最近变化时间（仅日志/诊断，不再卡 HTTP）
    var fieldCollectAt: [String: Date] = [:]
    /// 字段来源标记，便于日志排查
    var fieldSource: [String: String] = [:]
    /// BLE 本地锁/解锁保护截止时间
    var localDoorLockHoldUntil: Date?
    var httpTimer: Timer?
    var lastMQTTUpdate: Date?
    /// MQTT 车身字段最近 collectTime
    var lastMQTTBodyCollectAt: Date?
    var lastHTTPUpdate: Date?
    /// HTTP 车身字段最近 collectTime
    var lastHTTPBodyCollectAt: Date?
    var isConnecting = false

    let locationResolver = LocationResolver.shared
    let addressSettings: AddressServiceSettings
    private let displayCacheStore: VehicleDisplayCacheStore
    let keylessSettingsStore: KeylessSettingsStore
    let vehicleEventLogStore: VehicleEventLogStore
    let customVibrationStore: CustomVibrationStore
    let bleManager = VehicleBLEManager()

    var lastUnlockDecision: KeylessDecision?
    var lastLockDecision: KeylessDecision?
    var lastEvalLocked: Bool?
    var lastEvalNearby: Bool?
    var lastEvalFarAway: Bool?
    var phoneNearbySince: Date?
    var phoneFarAwaySince: Date?
    var bleScanStartedAt: Date?
    var hasCompletedBLEAuth = false
    var userManuallyStoppedBLE = false
    var lastAutoCommandAt: Date?
    var lastAutoCommandKind: VehicleCommandKind?
    var lastBLEWaitCommandKind: VehicleCommandKind?
    /// 手动锁/解锁后，短时间抑制无感反向动作，避免“刚锁上又被无感解开”
    var keylessManualSuppressUntil: Date?
    var keylessManualSuppressAction: KeylessAction?
    /// 钥匙材料可用时，离线/短时间不重复打 ble/key/query
    var lastBleKeyFetchAttemptAt: Date?
    var isFetchingBleKeyInfo = false
    var liveBLERawRSSI: Int?
    var liveBLERSSI: Int?
    var liveBLELastSeenAt: Date?
    var bleSignalLossWorkItem: DispatchWorkItem?
    var isExecutingKeylessCommand = false
    var isAppInForeground = true
    var didLogManualForegroundSkip = false
    var foregroundObserver: NSObjectProtocol?
    var backgroundObserver: NSObjectProtocol?
    var routeModeObserver: NSObjectProtocol?
    var lastObservedKeylessEnabled: Bool?
    var hasReceivedKeylessSettings = false
    var consecutiveScanTimeouts = 0 {
        didSet {
            if bleDiagnosticsStore.consecutiveScanTimeouts != consecutiveScanTimeouts {
                bleDiagnosticsStore.consecutiveScanTimeouts = consecutiveScanTimeouts
            }
        }
    }
    var ignoreNextBLEIdleCallback = false
    let bleDiagnosticsStore = BLEDiagnosticsStore.shared
    let nearbyBLEDevicesStore = NearbyBLEDevicesStore()
    var cancellables = Set<AnyCancellable>()

    init(
        addressSettings: AddressServiceSettings = .shared,
        credentialsStore: VehicleCredentialsStore = .shared,
        displayCacheStore: VehicleDisplayCacheStore = VehicleDisplayCacheStore(),
        keylessSettingsStore: KeylessSettingsStore = .shared,
        vehicleEventLogStore: VehicleEventLogStore = .shared,
        customVibrationStore: CustomVibrationStore = .shared
    ) {
        self.addressSettings = addressSettings
        self.credentialsStore = credentialsStore
        self.displayCacheStore = displayCacheStore
        self.keylessSettingsStore = keylessSettingsStore
        self.vehicleEventLogStore = vehicleEventLogStore
        self.customVibrationStore = customVibrationStore
        super.init(state: .placeholder, dashboard: VehicleDashboardState())
        VehicleStateStoreBridge.current = self
        reloadCachedBLEKeyInfo(preferScoped: true)
        loadPersistedDisplayCache()
        setupBLECallbacks()
        setupLifecycleObservers()
        setupRouteModeObserver()
        setupKeylessSettingsObserver()
        DispatchQueue.main.async { [weak self] in
            self?.autoConnect()
        }
    }

    deinit {
        httpTimer?.invalidate()
        mqtt?.disconnect()
        bleManager.stop()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }


    var canUseBLEForVehicleControl: Bool {
        bleManager.canSendVehicleControl
    }

    var canUseBLEForDoorLock: Bool {
        canUseBLEForVehicleControl
    }

    func sendCommandViaBLE(command: VehicleCommand, completion: @escaping (Result<Void, VehicleBLEManager.BLEControlError>) -> Void) {
        switch command.kind {
        case .lock:
            bleManager.sendDoorLockCommand(lock: true) { [weak self] result in
                if case .success = result {
                    // 手动/快捷锁车：抑制无感立刻反向解锁
                    let isKeyless = command.source == .keyless
                    self?.applyLocalDoorLockState(
                        locked: true,
                        source: isKeyless ? "无感锁车回包" : "BLE锁车回包",
                        suppressOppositeKeyless: !isKeyless
                    )
                }
                completion(result)
            }
        case .unlock:
            bleManager.sendDoorLockCommand(lock: false) { [weak self] result in
                if case .success = result {
                    let isKeyless = command.source == .keyless
                    self?.applyLocalDoorLockState(
                        locked: false,
                        source: isKeyless ? "无感解锁回包" : "BLE解锁回包",
                        suppressOppositeKeyless: !isKeyless
                    )
                }
                completion(result)
            }
        case .remoteStart:
            bleManager.sendPowerOnReadyCommand(completion: completion)
        case .remoteStop:
            bleManager.sendPowerOffCommand(completion: completion)
        default:
            completion(.failure(.frameBuildFailed))
        }
    }

    /// BLE 门锁成功后立即回写本地车锁，驱动快捷按钮与无感决策。
    func applyLocalDoorLockState(locked: Bool, source: String, suppressOppositeKeyless: Bool = false) {
        var next = state
        let previous = next.locked
        next.locked = locked
        // 本地刚确认过的门锁，刷新时间戳；不依赖网络回报
        let now = Date()
        next.timestamp = now
        // 保护窗：避免刚 BLE 锁/解锁就被旧 HTTP/MQTT 冲回
        localDoorLockHoldUntil = now.addingTimeInterval(Self.localLockHoldSeconds)
        fieldCollectAt["doorLockStatus"] = now
        fieldSource["doorLockStatus"] = "BLE"
        bumpStatusRevision()
        apply(next)

        var dash = dashboard
        // BLE 本地确认的锁态是实时的，去掉可能残留的“·缓存”后缀
        dash.lockStatusText = locked ? "已锁车" : "未锁"
        dash.updatedAt = now
        dash.updatedAtText = formatTime(now)
        applyDashboard(dash)

        if suppressOppositeKeyless {
            // 手动操作后至少压制 20s，或使用命令间隔的 3 倍
            let hold = max(20, keylessSettingsStore.settings.cmdInterval * 3)
            keylessManualSuppressUntil = Date().addingTimeInterval(hold)
            keylessManualSuppressAction = locked ? .unlock : .lock
            vehicleEventLogStore.add(
                .keyless,
                "无感临时抑制",
                detail: "手动\(locked ? "上锁" : "解锁")后 \(Int(hold))s 内不自动\(locked ? "解锁" : "上锁")"
            )
        }

        vehicleEventLogStore.add(
            .action,
            "本地车锁已更新",
            detail: "\(source) · \(previous.map { $0 ? "已锁" : "未锁" } ?? "未知") → \(locked ? "已锁" : "未锁")"
        )
        // 状态变了立刻重算无感
        evaluateKeylessAutomation(for: next)
    }

    func sendDoorLockViaBLE(command: VehicleCommand, completion: @escaping (Result<Void, VehicleBLEManager.BLEControlError>) -> Void) {
        sendCommandViaBLE(command: command, completion: completion)
    }


    func updateTokenSource(label: String, path: String = "") {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenSourceStore.update(label: normalizedLabel, path: normalizedPath)
        credentialsStore.tokenSourceLabel = normalizedLabel
        credentialsStore.tokenSourcePath = normalizedPath
    }

    func inferredTokenSourceLabel(from credentialsStore: VehicleCredentialsStore) -> String {
        let explicit = credentialsStore.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let path = credentialsStore.tokenSourcePath.lowercased()
        if path.contains("savedoauthmodel") && path.contains("appgroup") {
            return "五菱 App 自动读取"
        }
        if path.contains("savedoauthmodel") {
            return "手动导入 SavedOAuthModel"
        }
        return "手动输入 Token"
    }

    func applyCachedSnapshotIfAvailable() {
        // 只拿位置/地址兜底，不再把五菱 App 旧车身状态当实时状态写入。
        // 门/窗/锁/空调/电量等必须等 HTTP/MQTT 实时链路。
        guard let snapshot = WulingAppCacheReader.shared.readStatusCache() else { return }

        if let gcjLat = snapshot.latitude, let gcjLng = snapshot.longitude, gcjLat != 0, gcjLng != 0 {
            cachedLatitudeGcj = gcjLat
            cachedLongitudeGcj = gcjLng
            displayCacheStore.setCoordinate(latitudeGcj: gcjLat, longitudeGcj: gcjLng)
        }

        if let address = snapshot.address, !address.isEmpty {
            cachedAddress = address
            displayCacheStore.setAddress(address)
        }

        persistDisplayCache()
        CrashLogger.shared.mark("CACHE", "location-only from \(snapshot.sourcePath); body status waits for live HTTP/MQTT")
    }

    func loadPersistedDisplayCache() {
        let snapshot = displayCacheStore.loadSnapshot()
        if snapshot.latitudeGcj != 0, snapshot.longitudeGcj != 0 {
            cachedLatitudeGcj = snapshot.latitudeGcj
            cachedLongitudeGcj = snapshot.longitudeGcj
        }

        if !snapshot.address.isEmpty {
            cachedAddress = snapshot.address
        }
    }

    func persistDisplayCache() {
        if cachedLatitudeGcj != 0, cachedLongitudeGcj != 0 {
            displayCacheStore.setCoordinate(latitudeGcj: cachedLatitudeGcj, longitudeGcj: cachedLongitudeGcj)
        }

        let address = cachedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            displayCacheStore.setAddress(address)
        }
    }



    // MARK: - MQTT 显示信息

    var mqttClientId: String { credentials?.clientId ?? "" }
    var mqttBrokerDisplayText: String {
        guard let credentials else { return "" }
        return "\(credentials.broker):\(credentials.port)"
    }
    var mqttUsernameMasked: String { maskHex(credentials?.username, visiblePrefix: 4, visibleSuffix: 4) }
    var mqttPasswordMasked: String { maskHex(credentials?.password, visiblePrefix: 4, visibleSuffix: 4) }
    var mqttTopics: [String] { credentials?.topics ?? [] }
    var tokenSource: VehicleTokenSource? {
        let label = tokenSourceStore.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = tokenSourceStore.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty || !path.isEmpty else { return nil }
        return VehicleTokenSource(label: label.isEmpty ? "已配置凭据" : label, path: path)
    }


}
