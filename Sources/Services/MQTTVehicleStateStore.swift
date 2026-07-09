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

    enum LiveBLEStatus: Equatable {
        case disconnected
        case scanning
        case connecting
        case authenticating
        case authenticated
        case error
    }

    enum LiveMQTTStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error
    }

    @Published var bleStatus: LiveBLEStatus = .disconnected
    @Published var mqttStatus: LiveMQTTStatus = .disconnected
    @Published var authStatus: StatusAuthState = .expired("未登录")
    @Published var cachedLatitudeGcj: Double = 0
    @Published var cachedLongitudeGcj: Double = 0
    @Published var cachedAddress: String = ""
    @Published var liveLatitudeGcj: Double = 0
    @Published var liveLongitudeGcj: Double = 0
    @Published var liveAddress: String = ""
    @Published var latestBleKeyInfo: [String: String] = [:]
    @Published var latestBLEControlReceipt: VehicleBLEManager.BLEControlReceipt?
    @Published var latestControlResult: VehicleControlMQTTResult?
    @Published var debugBLERawRSSI: Int?
    @Published var debugBLESmoothedRSSI: Int?
    @Published var debugBLELastSeenText: String = "--"
    @Published var debugBLELastTransitionText: String = "--"
    @Published var tokenSourcePath: String = ""
    @Published var tokenSourceLabel: String = ""

    var displayLatitudeGcj: Double { liveLatitudeGcj != 0 ? liveLatitudeGcj : cachedLatitudeGcj }
    var displayLongitudeGcj: Double { liveLongitudeGcj != 0 ? liveLongitudeGcj : cachedLongitudeGcj }
    var displayAddress: String {
        let live = liveAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { return live }
        return cachedAddress
    }

    var mqtt: CocoaMQTT?
    var credentials: SGMWApiClient.MQTTCredentials?
    var credentialsStore: VehicleCredentialsStore

    var lastMqttFields: [String: String] = [:]
    var httpTimer: Timer?
    var lastMQTTUpdate: Date?
    var lastHTTPUpdate: Date?
    private var isConnecting = false

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
            bleManager.sendDoorLockCommand(lock: true, completion: completion)
        case .unlock:
            bleManager.sendDoorLockCommand(lock: false, completion: completion)
        case .remoteStart:
            bleManager.sendPowerOnReadyCommand(completion: completion)
        case .remoteStop:
            bleManager.sendPowerOffCommand(completion: completion)
        default:
            completion(.failure(.frameBuildFailed))
        }
    }

    func sendDoorLockViaBLE(command: VehicleCommand, completion: @escaping (Result<Void, VehicleBLEManager.BLEControlError>) -> Void) {
        sendCommandViaBLE(command: command, completion: completion)
    }


    private func updateTokenSource(label: String, path: String = "") {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenSourceLabel = normalizedLabel
        tokenSourcePath = normalizedPath
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
        guard let snapshot = WulingAppCacheReader.shared.readStatusCache() else { return }

        var cachedState = mapHTTPToVehicleState(snapshot.carStatus)
        cachedState.timestamp = Date()
        var cachedDashboard = mapHTTPToDashboard(snapshot.carStatus)
        cachedDashboard.updatedAt = Date()
        cachedDashboard.updatedAtText = formatTime(Date())

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
        apply(cachedState)
        applyDashboard(cachedDashboard)
        authStatus = .expired("缓存模式")
        CrashLogger.shared.mark("CACHE", "loaded Wuling cache from \(snapshot.sourcePath)")
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

    private func autoConnect() {
        userManuallyStoppedBLE = false
        // 离线 BLE：即使没有 token/网络，只要缓存了 BLE key 且无感开启，就走纯 BLE
        if keylessSettingsStore.settings.keylessEnabled || AppDiagnosticsSettings.vehicleControlRouteMode == .forceBLE {
            ensureBLESession(forceRestart: false, optimisticScanning: true)
        }

        let saved = credentialsStore
        if saved.isConfigured {
            start(with: saved)
            return
        }

        guard let tokenInfo = SGMWApiClient.shared.readLocalTokenInfo() else {
            mqttStatus = .disconnected
            if case .expired("缓存模式") = authStatus {
                CrashLogger.shared.mark("MQTT", "no local token found, keep cache mode")
            } else {
                authStatus = .expired("未读取到Token")
                CrashLogger.shared.mark("MQTT", "no local token found")
            }
            return
        }

        let token = tokenInfo.token
        updateTokenSource(label: "五菱 App 自动读取", path: tokenInfo.sourcePath)
        applyCachedSnapshotIfAvailable()

        authStatus = .valid
        SGMWApiClient.shared.queryDefaultCarResult(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let store = VehicleCredentialsStore.shared
                    store.accessToken = token
                    store.vin = info.vin
                    store.phone = info.phone
                    store.tokenSourceLabel = "五菱 App 自动读取"
                    store.tokenSourcePath = tokenInfo.sourcePath
                    self.start(with: store)
                case .failure(let error):
                    self.authStatus = .expired("车辆查询失败：\(error.localizedDescription)")
                    CrashLogger.shared.mark("HTTP", "queryDefaultCar failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func start(with credentialsStore: VehicleCredentialsStore) {
        self.credentialsStore = credentialsStore
        reloadCachedBLEKeyInfo(preferScoped: true)
        updateTokenSource(label: inferredTokenSourceLabel(from: credentialsStore), path: credentialsStore.tokenSourcePath)
        guard !isConnecting else { return }
        guard !credentialsStore.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authStatus = .expired("Token为空")
            mqttStatus = .disconnected
            return
        }
        guard !credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authStatus = .expired("VIN为空")
            mqttStatus = .disconnected
            return
        }

        isConnecting = true
        authStatus = .valid
        mqttStatus = .connecting

        // 先走 HTTP，拿到基础状态/经纬度/电量等
        startHTTPPolling(immediate: true)
        fetchBleKeyInfo()

        SGMWApiClient.shared.fetchMqttTokenResult(accessToken: credentialsStore.accessToken, vin: credentialsStore.vin) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isConnecting = false
                switch result {
                case .success(let mqttToken):
                    let creds = SGMWApiClient.shared.generateMQTTCredentials(vin: credentialsStore.vin, phone: credentialsStore.phone, mqttToken: mqttToken)
                    self.credentials = creds
                    self.connectMQTT(creds)
                case .failure(let error):
                    self.mqttStatus = .error
                    CrashLogger.shared.mark("MQTT", "mqtt token fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshNow() {
        lastMQTTUpdate = nil
        startHTTPPolling(immediate: true)
        fetchBleKeyInfo()
        if mqttStatus != .connected {
            reconnect()
        }
    }

    func reconnect() {
        mqtt?.disconnect()
        mqtt = nil
        credentials = nil
        lastMqttFields.removeAll()
        lastMQTTUpdate = nil
        start(with: credentialsStore)
    }


    // MARK: - State Merge

    func mergeHTTPBaseState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        let mergedBase = VehicleStateMerger.mergeHTTPBase(current: state, newState: newState)
        let merged = applyLiveBLEOverlay(to: mergedBase)
        apply(merged)

        let dash = VehicleStateMerger.mergeHTTPBaseDashboard(current: dashboard, newDashboard: newDashboard)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    func mergeRealtimeState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: newState)
        let merged = applyLiveBLEOverlay(to: mergedBase)
        apply(merged)

        let dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: newDashboard)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    func applyHTTPMeta(carInfo: [String: String], carStatus: [String: String]) {
        if let coordinate = VehicleHTTPMetaMapper.coordinate(from: carStatus) {
            liveLatitudeGcj = coordinate.latGcj
            liveLongitudeGcj = coordinate.lngGcj
            cachedLatitudeGcj = coordinate.latGcj
            cachedLongitudeGcj = coordinate.lngGcj
            if let addressHint = coordinate.addressHint, !addressHint.isEmpty {
                liveAddress = addressHint
                cachedAddress = addressHint
                persistDisplayCache()
            } else {
                persistDisplayCache()
            }
            locationResolver.getAddress(gcjLat: coordinate.latGcj, gcjLng: coordinate.lngGcj, address: coordinate.addressHint, amapWebKey: addressSettings.amapWebKey) { [weak self] resolved in
                guard let self, let resolved else { return }
                DispatchQueue.main.async {
                    self.liveAddress = resolved
                    self.cachedAddress = resolved
                    self.persistDisplayCache()
                }
            }
        }

        let dash = VehicleHTTPMetaMapper.dashboard(base: dashboard, carInfo: carInfo)
        if VehicleHTTPMetaMapper.supportsMQTT(carInfo: carInfo) {
            authStatus = .valid
        }
        applyDashboard(dash)

        let profile = VehicleHTTPMetaMapper.profile(carInfo: carInfo, carStatus: carStatus)
        applyProfile(profile)
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
        let label = tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = tokenSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty || !path.isEmpty else { return nil }
        return VehicleTokenSource(label: label.isEmpty ? "已配置凭据" : label, path: path)
    }


}
