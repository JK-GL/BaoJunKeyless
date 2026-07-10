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
    @Published var bleDiagnosticPhaseText: String = "待机"
    @Published var bleDiagnosticDetailText: String = "等待开始"
    @Published var bleDiagnosticLastConclusionText: String = "--"
    @Published var bleDiagnosticLastConclusionAtText: String = "--"
    @Published var bleDiagnosticLastReasonText: String = "--"
    @Published var bleDiagnosticNoDeviceCount: Int = 0
    @Published var bleDiagnosticFoundButNotConnectedCount: Int = 0
    @Published var bleDiagnosticAuthFailedCount: Int = 0
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
    var consecutiveScanTimeouts = 0
    var bleDidSeeDeviceThisCycle = false
    var bleDidReachConnectedThisCycle = false
    var bleCurrentCandidateName: String = "--"
    var bleCurrentCandidateRSSI: Int?
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


    func updateTokenSource(label: String, path: String = "") {
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
