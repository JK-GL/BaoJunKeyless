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
// 状态通道：
// - HTTP：完整车况快照，前台约 3s 补齐/收敛；关闭 MQTT 时作为唯一车况源
// - MQTT：官方实时字段有值即回写 UI（空/缺不覆盖），并触发 HTTP 补齐
// - BLE：锁/解/上电等近场控制与本地即时回写，最终仍由 MQTT/HTTP 收敛
// - 无感：RSSI 边沿 + KeylessDecisionEngine 评估后走 BLE/HTTP 执行链路
// - 控制路由：VehicleCommandExecutor（BLE 优先可用时走 BLE，否则/其余命令走 HTTP）
// 说明：本文件及 extension 只编排状态与执行；不直接改 UI 布局。

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
    /// 当前车身模型权威 collectTime
    var bodyCollectTime: Date?
    /// 字段最近变化时间（仅日志/诊断，不再卡 HTTP）
    var fieldCollectAt: [String: Date] = [:]
    /// 字段来源标记，便于日志排查
    var fieldSource: [String: String] = [:]
    /// 最近一次由明确字段或 BLE 成功回包确认的电源状态；HTTP 缺字段时短时保留。
    var lastExplicitPowerStateAt: Date?
    var lastExplicitPowerStateSource: String?
    static let explicitPowerStateHoldSeconds: TimeInterval = 180
    /// 兼容旧字段；本机锁保护已关闭，保持 nil。
    var localDoorLockHoldUntil: Date?
    /// 最近一次 MQTT 真实空调字段时间；用于防止更旧的 HTTP 快照把空调状态冲回。
    var lastMQTTClimateAt: Date?
    var httpTimer: Timer?
    /// HTTP 全量车况是状态页权威源；防止 3 秒轮询发生并发覆盖。
    var isHTTPPollInFlight = false
    var pendingHTTPPollAfterCurrent = false
    var pendingHTTPPollCompletions: [((Bool, String) -> Void)] = []
    /// MQTT / BLE 事件只负责唤醒一次 HTTP 权威刷新。
    var httpRefreshWakeWorkItem: DispatchWorkItem?
    var lastHTTPWakeRefreshAt: Date?
    /// 胎压独立接口低频拉取，避免每 3 秒额外请求一次。
    var lastTirePressureUpdate: Date?
    /// 车端 carInfo.conditionPollTime；实车日志为 3 秒。
    var vehicleHTTPPollInterval: TimeInterval = 3
    var lastMQTTUpdate: Date?
    /// MQTT 车身字段最近 collectTime
    var lastMQTTBodyCollectAt: Date?
    var lastHTTPUpdate: Date?
    /// 最近一次 HTTP 完整原始 carStatus；控制后核验必须读取这里，不能读取受 BLE 本地保护的 UI/state。
    var lastHTTPRawCarStatus: [String: String] = [:]
    var lastHTTPRawFetchedAt: Date?
    var lastHTTPRawGeneration: UInt64 = 0
    /// HTTP 车身字段最近 collectTime
    var lastHTTPBodyCollectAt: Date?
    /// HTTP 门窗快照：作为 MQTT/HTTP 对照基线，不再过滤 MQTT。
    var lastHTTPDoorWindowAuthority: (fields: [String: String], at: Date)?
    /// 自动轮询日志去重：状态指纹未变则不刷屏
    var lastHTTPPollLogFingerprint: String?
    var isConnecting = false
    var mqttConnectionGeneration = 0
    /// 门窗开闭权威字段（不含门锁）
    static let doorWindowOpenFieldKeys: [String] = [
        "doorOpenStatus",
        "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus",
        "tailDoorOpenStatus",
        "windowStatus",
        "window1Status", "window2Status", "window3Status", "window4Status",
        "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
        "window1HalfOpenStatus", "window2HalfOpenStatus", "window3HalfOpenStatus", "window4HalfOpenStatus",
        "windowHalfOpenStatus"
    ]

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
    var lastEvalInVehicleZone: Bool?
    var phoneNearbySince: Date?
    var phoneFarAwaySince: Date?
    /// 本会话是否进入过车区（强/近）。上锁必须先进入再离开。
    var hasEnteredVehicleZone = false
    /// 连续真实弱 RSSI 起始时间（信号丢失不算）
    var continuousWeakSince: Date?
    /// 自动解锁必须先经历真实离开；防止 App 恢复或车旁启动误解锁。
    var keylessUnlockDepartureObserved = false
    /// 离开后首次进入近场的边沿，只能消费一次。
    var keylessUnlockApproachEdgeArmed = false
    /// 三段 RSSI 语义，灰区不驱动动作。
    var keylessRSSIZone = "未知"
    var bleScanStartedAt: Date?
    var hasCompletedBLEAuth = false
    var userManuallyStoppedBLE = false
    var lastAutoCommandAt: Date?
    var lastAutoCommandKind: VehicleCommandKind?
    var lastBLEWaitCommandKind: VehicleCommandKind?
    /// 手动锁/解锁后，短时间抑制无感反向动作，避免“刚锁上又被无感解开”
    var keylessManualSuppressUntil: Date?
    var keylessManualSuppressAction: KeylessAction?
    /// 车端明确拒绝自动命令后，必须完成一次离开→再靠近才允许同类无感重试。
    var keylessRejectedActionUntilExit: KeylessAction?
    /// 检测到非本地 BLE 回写的外部锁态跃迁后，禁止车旁立即自动解锁。
    var externalLockRequiresExit = false
    var externalLockExitObserved = false
    /// 熄火监测门窗：是否处于提醒周期、上次推送时间、未关清单签名。
    var powerOffBodyMonitorActive = false
    var lastPowerOffBodyNotifyAt: Date?
    var lastPowerOffOpenPartsSignature = ""
    static let powerOffBodyNotifyInterval: TimeInterval = 10 * 60
    /// 熄火监测节流：避免同一次 HTTP 成功回调重复评估。
    var lastPowerOffBodyEvalGeneration: UInt64 = 0
    /// 应用刚发起的锁态命令；网络车况在短窗口内回报同方向变化时不视作外部锁车。
    var expectedAppLockState: Bool?
    var expectedAppLockStateUntil: Date?
    /// 钥匙材料可用时，离线/短时间不重复打 ble/key/query
    var lastBleKeyFetchAttemptAt: Date?
    var isFetchingBleKeyInfo = false
    var liveBLERawRSSI: Int?
    var liveBLERSSI: Int?
    var liveBLELastSeenAt: Date?
    var bleSignalLossWorkItem: DispatchWorkItem?
    var isExecutingKeylessCommand = false
    /// 无感上锁/解锁 HTTP 多轮确认序号；新命令会作废旧确认，避免串台推送。
    var keylessHTTPConfirmToken: UInt64 = 0
    var isAppInForeground = true
    var didLogManualForegroundSkip = false
    var foregroundObserver: NSObjectProtocol?
    var backgroundObserver: NSObjectProtocol?
    var routeModeObserver: NSObjectProtocol?
    var lastObservedKeylessEnabled: Bool?
    var lastObservedMQTTEnabled: Bool?
    var lastObservedLockUnlockConfirmationEnabled: Bool?
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

    /// 记录 App 已下发锁/解锁请求，供随后 HTTP/MQTT 状态回报做来源判定。
    func noteAppDoorLockCommand(_ locked: Bool) {
        expectedAppLockState = locked
        // 云端锁态常慢于 BLE；解锁后 HTTP 仍可能报已锁十余秒，窗要盖住多轮确认
        expectedAppLockStateUntil = Date().addingTimeInterval(45)
    }

    func sendCommandViaBLE(command: VehicleCommand, completion: @escaping (Result<Void, VehicleBLEManager.BLEControlError>) -> Void) {
        if command.kind == .lock || command.kind == .unlock {
            noteAppDoorLockCommand(command.kind == .lock)
        }
        switch command.kind {
        case .lock:
            bleManager.sendDoorLockCommand(lock: true) { [weak self] result in
                if case .success = result {
                    // 手动/快捷锁车：抑制无感立刻反向解锁
                    let isKeyless = command.source == .keyless
                    // 水管3：BLE 门锁本地短回写
                    self?.ingestBLEDoorLockLocal(
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
                    // 本 App 解锁成功：清掉误开的外部锁保护，恢复无感意义
                    self?.externalLockRequiresExit = false
                    self?.externalLockExitObserved = false
                    self?.ingestBLEDoorLockLocal(
                        locked: false,
                        source: isKeyless ? "无感解锁回包" : "BLE解锁回包",
                        suppressOppositeKeyless: !isKeyless
                    )
                }
                completion(result)
            }
        case .remoteStart:
            bleManager.sendPowerOnReadyCommand { [weak self] result in
                if case .success = result {
                    self?.ingestExplicitPowerLocal(.on, source: "BLE上电回包")
                    self?.scheduleHTTPRefreshFromRealtime(reason: "ble-power-on-result")
                }
                completion(result)
            }
        case .remoteStop:
            bleManager.sendPowerOffCommand { [weak self] result in
                if case .success = result {
                    self?.ingestExplicitPowerLocal(.off, source: "BLE熄火回包")
                    self?.scheduleHTTPRefreshFromRealtime(reason: "ble-power-off-result")
                }
                completion(result)
            }
        default:
            completion(.failure(.frameBuildFailed))
        }
    }

    /// 明确来源（HTTP/MQTT engineStatus 或 BLE 成功回包）确认电源状态。
    func applyExplicitPowerState(_ power: VehiclePowerState, source: String) {
        guard power != .unknown else { return }
        let now = Date()
        lastExplicitPowerStateAt = now
        lastExplicitPowerStateSource = source
        var next = state
        guard next.power != power else {
            // 同值重复确认：只记时间，不刷 UI。
            if next.timestamp != now {
                next.timestamp = now
                _ = apply(next)
            }
            return
        }
        next.power = power
        next.timestamp = now
        if apply(next) {
            bumpStatusRevision()
            evaluateKeylessAutomation(for: next)
            vehicleEventLogStore.add(.action, "车辆电源已确认", detail: "\(source) · \(power.title)")
        }
    }

    /// 空调真实字段回写。
    /// 只接受 MQTT / HTTP 返回的 acStatus、accCntTemp，不根据控制命令本地假改 UI。
    /// 相同值重复推送不会再次刷 UI，避免“开→开→开”连跳。
    @discardableResult
    func applyAuthoritativeClimateState(
        acOn: Bool? = nil,
        temperature: Double? = nil,
        source: String,
        observedAt: Date = Date(),
        scheduleHTTPConfirm: Bool = true
    ) -> Bool {
        guard acOn != nil || temperature != nil else { return false }
        var next = state
        var dash = dashboard
        var changed = false

        if let acOn, next.acOn != acOn {
            next.acOn = acOn
            changed = true
        }
        if let temperature {
            let clamped = max(17, min(33, temperature))
            if next.acTemperature != clamped {
                next.acTemperature = clamped
                changed = true
            }
            let text = "\(Int(clamped.rounded()))°C"
            if dash.acTemperatureText != text {
                dash.acTemperatureText = text
                changed = true
            }
        } else if let acOn {
            // MQTT 只推开关、没推温度时：
            // - 开：保留已有设定温度文案，不伪造新温度
            // - 关：显示关闭
            // 只有文案真的变化才算 changed，避免同态重复刷新。
            if acOn {
                if let current = next.acTemperature {
                    let text = "\(Int(current.rounded()))°C"
                    if dash.acTemperatureText != text {
                        dash.acTemperatureText = text
                        changed = true
                    }
                } else if dash.acTemperatureText == "--" || dash.acTemperatureText == "关闭" {
                    dash.acTemperatureText = "开启"
                    changed = true
                }
            } else if dash.acTemperatureText != "关闭" {
                dash.acTemperatureText = "关闭"
                changed = true
            }
        }

        // 同值重复推送不刷 UI，也不抬新鲜度，避免挡住后续 HTTP 温度。
        guard changed else { return false }

        // 只有真实变化才记录 MQTT 空调新鲜度，防止旧 HTTP 把开关冲回。
        if source.hasPrefix("MQTT") {
            if lastMQTTClimateAt == nil || observedAt > (lastMQTTClimateAt ?? .distantPast) {
                lastMQTTClimateAt = observedAt
            }
        }

        next.timestamp = observedAt
        next.online = true
        dash.updatedAt = observedAt
        dash.updatedAtText = formatTime(observedAt)
        if acOn != nil {
            fieldCollectAt["acStatus"] = observedAt
            fieldSource["acStatus"] = source
        }
        if temperature != nil {
            fieldCollectAt["accCntTemp"] = observedAt
            fieldSource["accCntTemp"] = source
        }

        let changedUI = applyVehicleSnapshot(state: next, dashboard: dash, bumpIfChanged: true)
        guard changedUI else { return false }
        vehicleEventLogStore.add(
            .action,
            "空调状态已确认",
            detail: "\(source) · 开关=\(next.acOn.map { $0 ? "开" : "关" } ?? "--") · 设定=\(next.acTemperature.map { "\(Int($0.rounded()))°C" } ?? "--")"
        )
        // 仅在空调真实变化后补一次 HTTP；同值重复推送不再触发。
        if scheduleHTTPConfirm {
            scheduleHTTPRefreshFromRealtime(reason: "mqtt-climate-confirmed")
        }
        return true
    }

    /// 网络权威车况确认“未锁→已锁”时，区分 App 自己的命令与外部/物理锁车。
    ///
    /// 重要：本 App 刚解锁后，云端 HTTP 常仍短暂回报「已锁」。
    /// 旧逻辑用「本地未锁 + HTTP 已锁」会误判成外部锁车，导致无感要求「离开再靠近」。
    func observeAuthoritativeLockState(_ locked: Bool?) {
        guard locked == true else { return }
        let now = Date()
        let expectWindowActive = expectedAppLockStateUntil.map { now <= $0 } ?? false

        // 本 App 刚上锁：网络回已锁属预期
        if expectWindowActive, expectedAppLockState == true {
            return
        }
        // 本 App 刚解锁：HTTP 仍显示已锁 = 云延迟，绝不是外部锁车
        if expectWindowActive, expectedAppLockState == false {
            return
        }
        // 本机锁保护已关闭：这里不再用本地保护窗跳过外部锁判断。
        // 仅当本地也认为未锁时，才可能是「外部把车锁上了」
        guard state.locked == false else { return }
        // 已在保护中不重复刷日志
        if externalLockRequiresExit { return }

        externalLockRequiresExit = true
        externalLockExitObserved = false
        vehicleEventLogStore.add(
            .keyless,
            "外部锁车保护开启",
            detail: "检测到非 App 锁车；需先离开后重新靠近，期间不自动解锁"
        )
    }

    /// 门锁本地回写（BLE 成功 / HTTP 受理 / MQTT 旁观等）。
    /// 本机锁保护已关闭：本地、MQTT、HTTP 谁新谁写，不再 15s 互挡。
    /// `protectAgainstNetworkOverride` 参数保留兼容调用点，当前不再开启保护窗。
    func applyLocalDoorLockState(
        locked: Bool,
        source: String,
        suppressOppositeKeyless: Bool = false,
        protectAgainstNetworkOverride: Bool = true
    ) {
        _ = protectAgainstNetworkOverride
        var next = state
        let previous = next.locked
        next.locked = locked
        // 本地刚确认过的门锁，刷新时间戳；不依赖网络回报
        let now = Date()
        next.timestamp = now
        localDoorLockHoldUntil = nil
        fieldCollectAt["doorLockStatus"] = now
        if source.hasPrefix("MQTT") {
            fieldSource["doorLockStatus"] = "MQTT"
        } else if source.hasPrefix("HTTP") {
            fieldSource["doorLockStatus"] = "HTTP"
        } else {
            fieldSource["doorLockStatus"] = "BLE"
        }

        var dash = dashboard
        // BLE 本地确认的锁态是实时的，去掉可能残留的“·缓存”后缀
        dash.lockStatusText = locked ? "已锁车" : "未锁"
        dash.updatedAt = now
        dash.updatedAtText = formatTime(now)
        // 同值门锁重复回写不刷 UI。
        guard applyVehicleSnapshot(state: next, dashboard: dash, bumpIfChanged: true) || previous != locked else {
            return
        }

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
        // BLE 锁态立即显示，同时唤醒 HTTP 完整快照确认其余车辆状态。
        scheduleHTTPRefreshFromRealtime(reason: "ble-door-lock-result")
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
        // 缓存位置恢复是正常路径，不写错误日志
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
