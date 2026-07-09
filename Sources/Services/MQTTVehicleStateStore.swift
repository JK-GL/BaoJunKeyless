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
    @Published var latestBleKeyInfo: [String: String] = VehicleBLEKeyCacheStore.load() ?? [:]
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

    private var mqtt: CocoaMQTT?
    private var credentials: SGMWApiClient.MQTTCredentials?
    var credentialsStore: VehicleCredentialsStore

    private var lastMqttFields: [String: String] = [:]
    private var httpTimer: Timer?
    var lastMQTTUpdate: Date?
    var lastHTTPUpdate: Date?
    private var isConnecting = false

    let locationResolver = LocationResolver.shared
    let addressSettings: AddressServiceSettings
    private let displayCacheStore: VehicleDisplayCacheStore
    private let keylessSettingsStore: KeylessSettingsStore
    private let vehicleEventLogStore: VehicleEventLogStore
    private let customVibrationStore: CustomVibrationStore
    private let bleManager = VehicleBLEManager()

    private var lastUnlockDecision: KeylessDecision?
    private var lastLockDecision: KeylessDecision?
    private var lastEvalLocked: Bool?
    private var lastEvalNearby: Bool?
    private var lastEvalFarAway: Bool?
    private var phoneNearbySince: Date?
    private var phoneFarAwaySince: Date?
    private var bleScanStartedAt: Date?
    private var hasCompletedBLEAuth = false
    private var userManuallyStoppedBLE = false
    private var lastAutoCommandAt: Date?
    private var lastAutoCommandKind: VehicleCommandKind?
    private var lastBLEWaitCommandKind: VehicleCommandKind?
    private var liveBLERawRSSI: Int?
    private var liveBLERSSI: Int?
    private var liveBLELastSeenAt: Date?
    private var bleSignalLossWorkItem: DispatchWorkItem?
    private var isExecutingKeylessCommand = false
    private var isAppInForeground = true
    private var didLogManualForegroundSkip = false
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var routeModeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

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

    private func setupBLECallbacks() {
        bleManager.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                // 丢弃过期 idle：stop() 的异步回调可能晚于新一轮 start()
                switch self.bleManager.state {
                case .scanning, .connecting, .connected, .authenticating, .authenticated:
                    return
                default:
                    break
                }
                let macSuffix = self.deviceDisplayName
                if self.bleStatus == .scanning {
                    let duration = self.formatElapsedSince(self.bleScanStartedAt ?? Date())
                    self.vehicleEventLogStore.add(.action, "BLE 扫描超时", detail: "\(macSuffix) · 已扫描 \(duration)，未发现设备")
                } else if self.bleStatus == .connecting || self.bleStatus == .authenticating || self.bleStatus == .authenticated {
                    let duration = self.formatElapsedSince(self.bleScanStartedAt ?? Date())
                    self.vehicleEventLogStore.add(.action, "BLE 已断开", detail: "\(macSuffix) · 扫描耗时 \(duration)")
                }
                self.bleStatus = .disconnected
                self.bleScanStartedAt = nil
                self.hasCompletedBLEAuth = false
                self.applyLiveBLERSSI(nil)
            case .unsupported, .bluetoothOff:
                self.bleStatus = .error
                self.bleScanStartedAt = nil
                self.hasCompletedBLEAuth = false
                self.applyLiveBLERSSI(nil)
                self.vehicleEventLogStore.add(.action, "BLE 不可用", detail: "蓝牙关闭或未授权")
            case .scanning:
                if self.bleScanStartedAt == nil {
                    self.bleScanStartedAt = Date()
                }
                if self.bleStatus != .scanning {
                    let timeout = Int(self.keylessSettingsStore.settings.bleScanDuration)
                    let interval = Int(self.keylessSettingsStore.settings.bleScanInterval)
                    let intervalText = interval <= 0 ? "无间隙" : "间隔 \(interval)s"
                    let macSuffix = self.deviceDisplayName
                    self.vehicleEventLogStore.add(.action, "BLE 扫描中", detail: "\(macSuffix) · 最长 \(timeout)s · \(intervalText)")
                }
                self.bleStatus = .scanning
            case .connecting, .connected:
                if self.bleStatus != .connecting {
                    let macSuffix = self.deviceDisplayName
                    self.vehicleEventLogStore.add(.action, "BLE 已连接", detail: "\(macSuffix) · 发现服务与特征中")
                }
                self.bleStatus = .connecting
            case .authenticating:
                self.vehicleEventLogStore.add(.action, "BLE 鉴权中", detail: "38C7/A857 四步鉴权")
                self.bleStatus = .authenticating
            case .authenticated:
                self.hasCompletedBLEAuth = true
                self.vehicleEventLogStore.add(.action, "BLE 鉴权成功", detail: "可发送控车命令")
                self.bleStatus = .authenticated
            case .authFailed(let reason):
                self.vehicleEventLogStore.add(.error, "BLE 鉴权失败", detail: reason)
                self.bleStatus = .error
                self.applyLiveBLERSSI(nil)
            case .error(let detail):
                self.vehicleEventLogStore.add(.error, "BLE 错误", detail: detail)
                self.bleStatus = .error
                self.applyLiveBLERSSI(nil)
            }
        }
        bleManager.onLog = { component, message in
            if let message {
                CrashLogger.shared.mark(component, message)
            }
        }
        bleManager.onControlReceipt = { [weak self] receipt in
            guard let self else { return }
            DispatchQueue.main.async {
                self.latestBLEControlReceipt = receipt
                self.vehicleEventLogStore.add(.action, "BLE 控制回包", detail: receipt.displayDetail)
            }
        }
        bleManager.onRSSIUpdate = { [weak self] rssi in
            guard let self else { return }
            DispatchQueue.main.async {
                self.applyLiveBLERSSI(rssi)
            }
        }
        bleManager.onControlCompletion = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.refreshNow()
            }
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

    private func refreshBLESessionIfNeeded() {
        let settings = keylessSettingsStore.settings
        let routeMode = AppDiagnosticsSettings.vehicleControlRouteMode
        let shouldKeepBLESession = settings.keylessEnabled || routeMode == .forceBLE
        guard shouldKeepBLESession else {
            bleManager.stop()
            bleStatus = .disconnected
            return
        }
        guard !userManuallyStoppedBLE else { return }
        let bleMac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? ""
        let keyId = latestBleKeyInfo["keyId"] ?? ""
        let masterKey = latestBleKeyInfo["masterKey"] ?? ""
        let keyMasterRandom = latestBleKeyInfo["keyMasterRandom"] ?? latestBleKeyInfo["random"] ?? ""
        let controlAes128Key = latestBleKeyInfo["controlAes128Key"]
        let bleType = latestBleKeyInfo["bleType"]
        let bleKey = latestBleKeyInfo["bleKey"]
        guard !bleMac.isEmpty, !keyId.isEmpty, !masterKey.isEmpty, !keyMasterRandom.isEmpty else {
            bleManager.stop()
            bleStatus = .disconnected
            return
        }
        // 时长/间隔始终热更新，即使会话已在扫描中
        bleManager.scanTimeoutDuration = max(20, min(300, settings.bleScanDuration))
        bleManager.scanRetryInterval = max(0, min(300, settings.bleScanInterval))
        bleManager.start(config: .init(bleMac: bleMac, keyId: keyId, masterKey: masterKey, keyMasterRandom: keyMasterRandom, controlAes128Key: controlAes128Key, bleType: bleType, bleKey: bleKey))
    }

    /// 确保本地有 BLE key 并启动会话。forceRestart=true 时先 stop 再 start，用于无感开关重新打开。
    private func ensureBLESession(forceRestart: Bool, optimisticScanning: Bool) {
        if forceRestart {
            userManuallyStoppedBLE = false
            bleManager.stop()
        }
        if latestBleKeyInfo.isEmpty, let cached = VehicleBLEKeyCacheStore.load(), !cached.isEmpty {
            latestBleKeyInfo = cached
        }
        if optimisticScanning,
           keylessSettingsStore.settings.keylessEnabled || AppDiagnosticsSettings.vehicleControlRouteMode == .forceBLE,
           !userManuallyStoppedBLE,
           hasUsableBLEKeyInfo {
            bleStatus = .scanning
        }
        refreshBLESessionIfNeeded()
        // 有网时顺带刷新 key；无 key 时必须走 fetch
        if !hasUsableBLEKeyInfo || forceRestart {
            fetchBleKeyInfo()
        }
    }

    private var hasUsableBLEKeyInfo: Bool {
        let bleMac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? ""
        let keyId = latestBleKeyInfo["keyId"] ?? ""
        let masterKey = latestBleKeyInfo["masterKey"] ?? ""
        let keyMasterRandom = latestBleKeyInfo["keyMasterRandom"] ?? latestBleKeyInfo["random"] ?? ""
        return !bleMac.isEmpty && !keyId.isEmpty && !masterKey.isEmpty && !keyMasterRandom.isEmpty
    }

    private func setupLifecycleObservers() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isAppInForeground = true
            self.didLogManualForegroundSkip = false
            // 前台恢复不覆盖手动停止；只有未手动停时才恢复扫描
            if !self.userManuallyStoppedBLE {
                self.ensureBLESession(forceRestart: false, optimisticScanning: true)
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isAppInForeground = false
            self.didLogManualForegroundSkip = false
        }
    }

    private func setupRouteModeObserver() {
        routeModeObserver = NotificationCenter.default.addObserver(
            forName: .vehicleControlRouteModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.bleManager.stop()
            self.userManuallyStoppedBLE = false
            self.ensureBLESession(forceRestart: false, optimisticScanning: true)
        }
    }

    private var lastObservedKeylessEnabled: Bool?
    private var hasReceivedKeylessSettings = false

    private func setupKeylessSettingsObserver() {
        lastObservedKeylessEnabled = keylessSettingsStore.settings.keylessEnabled
        keylessSettingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                let isFirst = !self.hasReceivedKeylessSettings
                self.hasReceivedKeylessSettings = true
                let wasEnabled = self.lastObservedKeylessEnabled
                self.lastObservedKeylessEnabled = settings.keylessEnabled

                if isFirst {
                    // 初始化首次事件交给 autoConnect，这里只同步参数
                    self.refreshBLESessionIfNeeded()
                    return
                }

                if settings.keylessEnabled {
                    let justEnabled = wasEnabled != true
                    if justEnabled {
                        // 关 → 开：清手动停止，强制重启，立刻扫
                        self.ensureBLESession(forceRestart: true, optimisticScanning: true)
                        self.vehicleEventLogStore.add(.action, "BLE 自动扫描", detail: "无感开关已开启")
                    } else {
                        // 其它设置变更：只同步时长/间隔，不强制打断当前会话
                        self.refreshBLESessionIfNeeded()
                    }
                } else {
                    self.userManuallyStoppedBLE = false
                    self.bleManager.stop()
                    self.bleStatus = .disconnected
                    if wasEnabled != false {
                        self.resetKeylessRuntimeState()
                        self.vehicleEventLogStore.add(.action, "BLE 已停止", detail: "无感开关已关闭")
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func resetKeylessRuntimeState() {
        lastUnlockDecision = nil
        lastLockDecision = nil
        lastEvalLocked = nil
        lastEvalNearby = nil
        lastEvalFarAway = nil
        phoneNearbySince = nil
        phoneFarAwaySince = nil
        bleScanStartedAt = nil
        hasCompletedBLEAuth = false
        userManuallyStoppedBLE = false
        didLogManualForegroundSkip = false
        lastBLEWaitCommandKind = nil
        bleSignalLossWorkItem?.cancel()
        bleSignalLossWorkItem = nil
        isExecutingKeylessCommand = false
    }

    private func applyLiveBLEOverlay(to baseState: VehicleState) -> VehicleState {
        guard let rssi = liveBLERSSI else { return baseState }
        var next = baseState
        next.bleRssi = rssi
        next.phoneNearby = resolvedPhoneNearby(for: rssi, previous: baseState.phoneNearby)
        return next
    }

    private func resolvedPhoneNearby(for smoothedRSSI: Int, previous: Bool) -> Bool {
        if previous {
            return Double(smoothedRSSI) > keylessSettingsStore.settings.lockThreshold
        }
        return Double(smoothedRSSI) >= keylessSettingsStore.settings.unlockThreshold
    }

    private func scheduleBLESignalLossTimeout() {
        bleSignalLossWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.liveBLERawRSSI = nil
            self.liveBLERSSI = nil
            self.liveBLELastSeenAt = nil
            self.debugBLERawRSSI = nil
            self.debugBLESmoothedRSSI = nil
            self.debugBLELastSeenText = "--"
            self.debugBLELastTransitionText = "BLE信号丢失 · \(formatTime(Date()))"
            self.vehicleEventLogStore.add(.warning, "BLE信号丢失", detail: "连续 3s 未收到 RSSI，按远离处理")
            var next = self.state
            next.bleRssi = nil
            next.phoneNearby = false
            self.apply(next)
            self.evaluateKeylessAutomation(for: next)
        }
        bleSignalLossWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func applyLiveBLERSSI(_ rawRSSI: Int?) {
        guard let rawRSSI else {
            liveBLERawRSSI = nil
            liveBLERSSI = nil
            liveBLELastSeenAt = nil
            debugBLERawRSSI = nil
            debugBLESmoothedRSSI = nil
            debugBLELastSeenText = "--"
            bleSignalLossWorkItem?.cancel()
            bleSignalLossWorkItem = nil
            var next = state
            next.bleRssi = nil
            next.phoneNearby = false
            apply(next)
            evaluateKeylessAutomation(for: next)
            return
        }

        let previousNearby = state.phoneNearby
        liveBLERawRSSI = rawRSSI
        liveBLELastSeenAt = Date()
        if let current = liveBLERSSI {
            let alpha = 0.35
            let smoothed = Int((Double(current) * (1 - alpha) + Double(rawRSSI) * alpha).rounded())
            liveBLERSSI = smoothed
        } else {
            liveBLERSSI = rawRSSI
        }
        let smoothedRSSI = liveBLERSSI ?? rawRSSI
        debugBLERawRSSI = rawRSSI
        debugBLESmoothedRSSI = smoothedRSSI
        debugBLELastSeenText = formatTime(Date())
        scheduleBLESignalLossTimeout()

        var next = state
        next.bleRssi = smoothedRSSI
        next.phoneNearby = resolvedPhoneNearby(for: smoothedRSSI, previous: previousNearby)
        apply(next)
        evaluateKeylessAutomation(for: next)

        if previousNearby != next.phoneNearby {
            let detail = "raw=\(rawRSSI), smoothed=\(smoothedRSSI), unlock=\(Int(keylessSettingsStore.settings.unlockThreshold)), lock=\(Int(keylessSettingsStore.settings.lockThreshold))"
            debugBLELastTransitionText = "\(next.phoneNearby ? "靠近" : "远离") · \(formatTime(Date()))"
            vehicleEventLogStore.add(.keyless, next.phoneNearby ? "BLE判定靠近" : "BLE判定远离", detail: detail)
        }
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

    private func evaluateKeylessAutomation(for currentState: VehicleState) {
        let settings = keylessSettingsStore.settings
        guard settings.keylessEnabled else {
            resetKeylessRuntimeState()
            return
        }
        if settings.appManual {
            guard !isAppInForeground else {
                if !didLogManualForegroundSkip {
                    vehicleEventLogStore.add(.keyless, "前台手动", detail: "App 在前台时不自动执行无感命令")
                    didLogManualForegroundSkip = true
                }
                return
            }
        } else {
            didLogManualForegroundSkip = false
        }
        guard settings.pluginTakeover || settings.smartSwitch || settings.appManual else { return }

        // 指纹去重：车锁状态 + 手机位置都没变 → 不评估
        // 但如果有延迟计时器在跑（靠近后等待解锁/远离后等待锁车），必须继续评估以检查延迟到期
        let hasActiveUnlockDelay = currentState.phoneNearby
            && phoneNearbySince != nil
            && settings.unlockEnabled
            && settings.unlockApproachDuration > 0
        let hasActiveLockDelay = currentState.phoneFarAway
            && phoneFarAwaySince != nil
            && settings.lockEnabled
            && settings.lockDelay > 0
        let hasActiveDelay = hasActiveUnlockDelay || hasActiveLockDelay
        let fingerprint = (currentState.locked, currentState.phoneNearby, currentState.phoneFarAway)
        if fingerprint == (lastEvalLocked, lastEvalNearby, lastEvalFarAway) && !hasActiveDelay {
            return
        }
        lastEvalLocked = fingerprint.0
        lastEvalNearby = fingerprint.1
        lastEvalFarAway = fingerprint.2

        // 状态过期 → 不评估，不记日志
        guard currentState.isFresh() else { return }

        // 无感上锁安全门：必须本次 BLE 会话曾鉴权成功，否则不评估上锁
        if currentState.phoneFarAway && !hasCompletedBLEAuth {
            return
        }

        if currentState.phoneNearby {
            if phoneNearbySince == nil {
                phoneNearbySince = Date()
            }
        } else {
            phoneNearbySince = nil
        }

        if currentState.phoneFarAway {
            if phoneFarAwaySince == nil {
                phoneFarAwaySince = Date()
                if settings.lockEnabled {
                    vehicleEventLogStore.add(.keyless, "上锁等待", detail: "手机远离，等待 \(Int(settings.lockDelay))s")
                }
            }
        } else {
            phoneFarAwaySince = nil
        }

        let unlockDecision = KeylessDecisionEngine.evaluateUnlockWithDelay(state: currentState, settings: settings, phoneNearbySince: phoneNearbySince)
        if unlockDecision != lastUnlockDecision {
            let detail = KeylessDecisionEngine.logDetail(decision: unlockDecision, state: currentState, settings: settings)
            switch unlockDecision {
            case .allow:
                vehicleEventLogStore.add(.keyless, "解锁允许", detail: detail)
            case .deny:
                vehicleEventLogStore.add(.keyless, "解锁拒绝", detail: detail)
            case .wait:
                vehicleEventLogStore.add(.keyless, "解锁等待", detail: detail)
            }
            lastUnlockDecision = unlockDecision
        }
        if case .allow = unlockDecision {
            executeKeylessCommandIfNeeded(action: .unlock, state: currentState, reason: unlockDecision.reason)
        }

        let lockDecision = evaluateLockDecisionWithDelay(state: currentState, settings: settings)
        if lockDecision != lastLockDecision {
            let detail = KeylessDecisionEngine.logDetail(decision: lockDecision, state: currentState, settings: settings)
            switch lockDecision {
            case .allow:
                vehicleEventLogStore.add(.keyless, "上锁允许", detail: detail)
            case .deny:
                vehicleEventLogStore.add(.keyless, "上锁拒绝", detail: detail)
            case .wait:
                vehicleEventLogStore.add(.keyless, "上锁等待", detail: detail)
            }
            lastLockDecision = lockDecision
        }
        if case .allow = lockDecision {
            executeKeylessCommandIfNeeded(action: .lock, state: currentState, reason: lockDecision.reason)
        }
    }

    private func evaluateLockDecisionWithDelay(state: VehicleState, settings: KeylessSettings) -> KeylessDecision {
        let decision = KeylessDecisionEngine.evaluateLock(state: state, settings: settings)
        guard case .allow = decision else { return decision }
        let delay = max(settings.lockDelay, 0)
        guard delay > 0 else { return decision }
        guard let farSince = phoneFarAwaySince else {
            return .wait(action: .lock, reason: "手机远离，等待上锁延迟")
        }
        let elapsed = Date().timeIntervalSince(farSince)
        guard elapsed >= delay else {
            return .wait(action: .lock, reason: "手机远离，等待上锁延迟")
        }
        return decision
    }

    private func executeKeylessCommandIfNeeded(action: KeylessAction, state: VehicleState, reason: String) {
        guard !isExecutingKeylessCommand else { return }
        let settings = keylessSettingsStore.settings
        if let lastAutoCommandAt,
           Date().timeIntervalSince(lastAutoCommandAt) < settings.cmdInterval {
            return
        }

        let command: VehicleCommand
        switch action {
        case .unlock:
            command = VehicleCommand(kind: .unlock, title: "无感解锁", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .httpControl)
        case .lock:
            command = VehicleCommand(kind: .lock, title: "无感上锁", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .httpControl)
        }

        guard bleManager.canSendDoorLockControl else {
            if lastBLEWaitCommandKind != command.kind {
                vehicleEventLogStore.add(.keyless, "无感等待BLE", detail: "\(command.title) | BLE 未鉴权成功")
                lastBLEWaitCommandKind = command.kind
            }
            return
        }
        lastBLEWaitCommandKind = nil
        isExecutingKeylessCommand = true
        lastAutoCommandAt = Date()
        lastAutoCommandKind = command.kind
        vehicleEventLogStore.add(.keyless, "无感命令发送", detail: "\(command.title) | \(reason)")

        let transport = BLEDoorLockTransport(bleController: self)
        VehicleCommandExecutor.executeAsync(command, transport: transport, refresher: self) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isExecutingKeylessCommand = false
                let category: VehicleEventLogCategory
                switch result.state {
                case .failed(_), .timedOut(_):
                    category = .error
                default:
                    category = .keyless
                }
                let detail = result.userMessage.isEmpty ? result.command.title : "\(result.command.title)：\(result.userMessage)"
                self.vehicleEventLogStore.add(category, "无感命令结果", detail: detail)
                self.postKeylessNotificationIfNeeded(for: action, result: result)
                if case .sent = result.state {
                    self.playKeylessVibrationIfNeeded(for: action)
                }
                if case .completed = result.state {
                    self.playKeylessVibrationIfNeeded(for: action)
                }
            }
        }
    }

    private func playKeylessVibrationIfNeeded(for action: KeylessAction) {
        let settings = keylessSettingsStore.settings
        switch action {
        case .unlock:
            guard settings.unlockVibrate else { return }
            playVibration(choice: keylessSettingsStore.unlockVibChoice(), intensity: settings.unlockVibStrength / 100.0)
        case .lock:
            guard settings.lockVibrate else { return }
            playVibration(choice: keylessSettingsStore.lockVibChoice(), intensity: settings.lockVibStrength / 100.0)
        }
    }

    private func postKeylessNotificationIfNeeded(for action: KeylessAction, result: VehicleCommandExecutionResult) {
        let settings = keylessSettingsStore.settings
        let popupEnabled: Bool
        switch action {
        case .unlock:
            popupEnabled = settings.unlockPopup
        case .lock:
            popupEnabled = settings.lockPopup
        }
        guard popupEnabled else { return }

        let actionTitle = action.title
        let title: String
        switch result.state {
        case .sent, .completed:
            title = "无感\(actionTitle)已触发"
        case .failed(_), .timedOut(_):
            title = "无感\(actionTitle)失败"
        case .feedbackOnly, .planned:
            return
        }
        let body = result.userMessage.isEmpty ? result.command.detail : result.userMessage
        AppNotificationManager.shared.postKeylessNotification(title: title, body: body)
    }

    private func playVibration(choice: VibrationChoice, intensity: Double) {
        switch choice {
        case .preset(let pattern):
            pattern.play(intensity: intensity)
        case .custom(let id):
            if let pattern = customVibrationStore.patterns.first(where: { $0.id == id }) {
                pattern.play(intensity: intensity)
            }
        }
    }

    // MARK: - HTTP 轮询

    func startHTTPPolling(immediate: Bool) {
        httpTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollHTTPOnce()
        }
        httpTimer = timer
        if immediate { pollHTTPOnce() }
    }

    private func pollHTTPOnce() {
        let store = credentialsStore
        let token = store.accessToken
        guard !token.isEmpty else { return }

        VehicleHTTPRefreshRequester.shared.fetch(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard case .success(let refreshResult) = result else { return }
                self.lastHTTPUpdate = refreshResult.fetchedAt
                let newState = self.mapHTTPToVehicleState(refreshResult.carStatus)
                var newDashboard = self.mapHTTPToDashboard(refreshResult.carStatus)
                if !refreshResult.tirePressure.isEmpty {
                    newDashboard = VehicleStatusMapper.tirePressureDashboard(from: refreshResult.tirePressure, base: newDashboard)
                }
                let shouldUseHTTP = self.lastMQTTUpdate.map { Date().timeIntervalSince($0) >= 60 } ?? true

                self.mergeHTTPBaseState(newState: newState, dashboard: newDashboard)
                if shouldUseHTTP {
                    self.apply(newState)
                    self.applyDashboard(newDashboard)
                }

                self.applyHTTPMeta(carInfo: refreshResult.carInfo, carStatus: refreshResult.carStatus)
                CrashLogger.shared.mark("HTTP", "status updated")
            }
        }
    }

    // MARK: - BLE 钥匙查询

    private func fetchBleKeyInfo() {
        let store = credentialsStore
        guard !store.accessToken.isEmpty, !store.vin.isEmpty, !store.phone.isEmpty else {
            // 无 token 时仍可尝试用缓存的 BLE key（官方 App 离线模式的核心逻辑）
            if let cached = VehicleBLEKeyCacheStore.load(), !cached.isEmpty {
                self.latestBleKeyInfo = cached
                self.refreshBLESessionIfNeeded()
            }
            return
        }
        SGMWApiClient.shared.queryBleKeyResult(accessToken: store.accessToken, vin: store.vin, phone: store.phone) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard case .success(let info) = result else {
                    // HTTP 失败 → 回退到本地缓存
                    if let cached = VehicleBLEKeyCacheStore.load(), !cached.isEmpty {
                        self.latestBleKeyInfo = cached
                        self.refreshBLESessionIfNeeded()
                    }
                    return
                }
                VehicleBLEKeyCacheStore.save(info)  // 写盘，支持下次离线
                self.latestBleKeyInfo = info
                self.refreshBLESessionIfNeeded()
                var dash = self.dashboard
                dash.bleMacText = info["bleMac"] ?? info["macAddress"] ?? dash.bleMacText
                dash.keyIdText = info["keyId"] ?? dash.keyIdText
                dash.keyTypeText = info["keyType"] ?? dash.keyTypeText
                dash.masterKeyMaskedText = maskHex(info["masterKey"], visiblePrefix: 4, visibleSuffix: 4)
                dash.randomMaskedText = maskHex(info["keyMasterRandom"] ?? info["random"], visiblePrefix: 4, visibleSuffix: 4)
                dash.keyExpiryText = info["expiredTime"] ?? info["expireTime"] ?? info["endTime"] ?? dash.keyExpiryText
                dash.vehicleInfoUpdatedAtText = formatDateTime(Date())
                self.applyDashboard(dash)
            }
        }
    }

    // MARK: - MQTT

    private func connectMQTT(_ creds: SGMWApiClient.MQTTCredentials) {
        let mqtt = CocoaMQTT(clientID: creds.clientId, host: creds.broker, port: creds.port)
        mqtt.username = creds.username
        mqtt.password = creds.password
        mqtt.keepAlive = 60
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.delegate = self
        self.mqtt = mqtt
        CrashLogger.shared.mark("MQTT", "connecting clientId=\(creds.clientId)")
        if !mqtt.connect() {
            mqttStatus = .error
            CrashLogger.shared.mark("MQTT", "connect initiate failed")
        }
    }

    private func handleVehicleStatus(_ data: Data) {
        let fields = decodeMQTTFields(data)
        guard !fields.isEmpty else { return }

        var changedKeys: [String] = []
        for (k, v) in fields where lastMqttFields[k] != v {
            changedKeys.append("\(k):\(lastMqttFields[k] ?? "?")→\(v)")
        }
        guard !changedKeys.isEmpty else { return }

        lastMqttFields.merge(fields) { _, new in new }
        let newState = mapMQTTToVehicleState(fields)
        let newDashboard = mapMQTTToDashboard(fields)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected
            self.mergeRealtimeState(newState: newState, dashboard: newDashboard)
            let summary = changedKeys.prefix(6).joined(separator: ", ")
            CrashLogger.shared.mark("MQTT", "state changed: \(summary)")
        }
    }

    private func handleVehicleControlResult(_ data: Data) {
        guard let result = decodeControlResult(data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mqttStatus = .connected
            self.latestControlResult = result
            CrashLogger.shared.mark("MQTT", "control result: \(result.displayDetail)")
        }
    }

    private func decodeControlResult(_ data: Data) -> VehicleControlMQTTResult? {
        let decoded = ProtobufDecoder.decode(data)
        guard !decoded.isEmpty else { return decodeJSONControlResult(data) }
        var resultCode = ""
        var message = ""
        var serviceCode = ""
        var timestampMillis: Int64?

        for field in decoded {
            switch field.fieldNumber {
            case 1:
                resultCode = ProtobufDecoder.string(field) ?? ProtobufDecoder.int64(field).map { String($0) } ?? resultCode
            case 2:
                message = ProtobufDecoder.string(field) ?? message
            case 3:
                serviceCode = ProtobufDecoder.string(field) ?? serviceCode
            case 4:
                timestampMillis = ProtobufDecoder.int64(field) ?? timestampMillis
            default:
                continue
            }
        }

        guard !resultCode.isEmpty || !message.isEmpty || !serviceCode.isEmpty else { return decodeJSONControlResult(data) }
        return VehicleControlMQTTResult(resultCode: resultCode, message: message, serviceCode: serviceCode, timestampMillis: timestampMillis, receivedAt: Date())
    }

    private func decodeJSONControlResult(_ data: Data) -> VehicleControlMQTTResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let dataObject = json["data"] as? [String: Any]
        let source = dataObject ?? json
        let resultCode = stringValue(source["resultCode"] ?? source["code"] ?? source["result"])
        let message = stringValue(source["message"] ?? source["msg"])
        let serviceCode = stringValue(source["serviceCode"] ?? source["service"] ?? source["field"])
        let timestampMillis = int64Value(source["timestamp"] ?? source["time"] ?? source["ts"])
        guard !resultCode.isEmpty || !message.isEmpty || !serviceCode.isEmpty else { return nil }
        return VehicleControlMQTTResult(resultCode: resultCode, message: message, serviceCode: serviceCode, timestampMillis: timestampMillis, receivedAt: Date())
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return ""
        }
    }

    private func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        default:
            return nil
        }
    }

    private func decodeMQTTFields(_ data: Data) -> [String: String] {
        let decoded = ProtobufDecoder.decode(data)
        let nameMap: [Int: String] = [
            1: "collectTime", 2: "acStatus", 3: "doorLockStatus",
            4: "door1LockStatus", 5: "door2LockStatus", 6: "door3LockStatus", 7: "door4LockStatus", 8: "tailDoorLockStatus",
            9: "door1OpenStatus", 10: "door2OpenStatus", 11: "door3OpenStatus", 12: "door4OpenStatus", 13: "tailDoorOpenStatus",
            14: "window1Status", 15: "window2Status", 16: "window3Status", 17: "window4Status",
            18: "window1OpenDegree", 19: "window2OpenDegree", 20: "window3OpenDegree", 21: "window4OpenDegree"
        ]
        var result: [String: String] = [:]
        for field in decoded {
            guard let name = nameMap[field.fieldNumber] else { continue }
            switch field.wireType {
            case .varint:
                if let val = ProtobufDecoder.int64(field) { result[name] = String(val) }
            case .lengthDelimited:
                if let val = ProtobufDecoder.string(field) { result[name] = val }
            }
        }
        return result
    }

    // MARK: - HTTP/MQTT 映射

    func mapHTTPToVehicleState(_ s: [String: String]) -> VehicleState {
        VehicleStatusMapper.httpState(from: s, base: state)
    }

    func mapHTTPToDashboard(_ s: [String: String]) -> VehicleDashboardState {
        VehicleStatusMapper.httpDashboard(from: s, base: dashboard)
    }

    private func mapMQTTToVehicleState(_ s: [String: String]) -> VehicleState {
        VehicleStatusMapper.mqttState(from: s, base: state)
    }

    private func mapMQTTToDashboard(_ s: [String: String]) -> VehicleDashboardState {
        VehicleStatusMapper.mqttDashboard(from: s, base: dashboard)
    }

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

    // MARK: - MQTT Delegate 事件入口

    func handleMQTTConnectAck(_ mqtt: CocoaMQTT, ack: CocoaMQTTConnAck) {
        if ack == .accept {
            mqttStatus = .connected
            CrashLogger.shared.mark("MQTT", "connected (ack=\(ack.rawValue))")
            guard let creds = credentials else { return }
            for topic in creds.topics {
                mqtt.subscribe(topic, qos: .qos1)
            }
        } else {
            mqttStatus = .error
            CrashLogger.shared.mark("MQTT", "connect rejected: \(ack.rawValue)")
        }
    }

    func handleMQTTReceivedMessage(_ message: CocoaMQTTMessage) {
        let payload = Data(message.payload)
        if message.topic.hasSuffix("/vehicle/app/status") {
            handleVehicleStatus(payload)
        } else if message.topic.hasSuffix("/vehicle/control") {
            handleVehicleControlResult(payload)
        }
    }

    func handleMQTTSubscribedTopics(success: NSDictionary, failed: [String]) {
        CrashLogger.shared.mark("MQTT", "subscribed \(success.count) topics, failed \(failed.count)")
    }

    func handleMQTTDisconnect(error: Error?) {
        mqttStatus = .error
        CrashLogger.shared.mark("MQTT", "disconnected: \(error?.localizedDescription ?? "no error")")
    }

    private func formatElapsedSince(_ start: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed < 60 { return "\(elapsed)s" }
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return "\(minutes)m\(seconds)s"
    }

    private var deviceDisplayName: String {
        let mac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? ""
        let cleaned = mac.uppercased().filter { $0.isLetter || $0.isNumber }
        if cleaned.count >= 12 {
            var parts: [String] = []
            for i in stride(from: 0, to: 12, by: 2) {
                let start = cleaned.index(cleaned.startIndex, offsetBy: i)
                let end = cleaned.index(start, offsetBy: 2)
                parts.append(String(cleaned[start..<end]))
            }
            return parts.joined(separator: ":")
        }
        return mac.isEmpty ? "--" : mac
    }

    func toggleBLEScanning() {
        let isActive = bleStatus == .scanning || bleStatus == .connecting || bleStatus == .authenticating || bleStatus == .authenticated
        if isActive {
            userManuallyStoppedBLE = true
            bleStatus = .disconnected
            bleManager.stop()
            vehicleEventLogStore.add(.action, "BLE 手动停止", detail: "用户取消扫描")
        } else {
            userManuallyStoppedBLE = false
            ensureBLESession(forceRestart: true, optimisticScanning: true)
            vehicleEventLogStore.add(.action, "BLE 手动扫描", detail: "用户触发扫描")
        }
    }
}
