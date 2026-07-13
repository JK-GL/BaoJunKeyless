import SwiftUI

// MARK: - 震动选择类型
enum VibrationChoice: Hashable {
    case preset(VibrationPattern)
    case custom(UUID)
}

struct KeylessView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var customStore: CustomVibrationStore

    @State private var showUnlockRecorder = false
    @State private var showLockRecorder = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "无感车控")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                KeylessMainSection(setMode: setMode)
                KeylessRealtimeStatusHost()
                KeylessRecentActivitySection()
                if settingsStore.settings.keylessEnabled {
                    UnlockSettingsSection(
                        showRecorder: $showUnlockRecorder,
                        choice: unlockVibChoiceBinding,
                        customStore: customStore
                    )
                    LockSettingsSection(
                        showRecorder: $showLockRecorder,
                        choice: lockVibChoiceBinding,
                        customStore: customStore
                    )
                }

                Spacer(minLength: 100)
            }
        }
        .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
        .onDisappear {
            scrollState.reset()
        }
        .sheet(isPresented: $showUnlockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setUnlockVibChoice(.custom(pattern.id))
                VehicleEventLogStore.shared.add(.keyless, "录制解锁震动", detail: pattern.name)
            }
        }
        .sheet(isPresented: $showLockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setLockVibChoice(.custom(pattern.id))
                VehicleEventLogStore.shared.add(.keyless, "录制上锁震动", detail: pattern.name)
            }
        }
    }

    private func setMode(_ mode: KeylessControlMode) {
        // 智能切换 UI 已移除；选插件/前台时清掉 smartSwitch，避免互斥残留
        settingsStore.settings.pluginTakeover = (mode == .plugin)
        settingsStore.settings.smartSwitch = false
        settingsStore.settings.appManual = (mode == .manual)

        let text: String
        switch mode {
        case .plugin: text = "插件托管"
        case .smart: text = "智能切换" // 兼容枚举残留
        case .manual: text = "前台手动"
        }
        VehicleEventLogStore.shared.add(.keyless, "切换无感模式", detail: text)
    }

    private var unlockVibChoiceBinding: Binding<VibrationChoice> {
        Binding(
            get: { settingsStore.unlockVibChoice() },
            set: { settingsStore.setUnlockVibChoice($0) }
        )
    }

    private var lockVibChoiceBinding: Binding<VibrationChoice> {
        Binding(
            get: { settingsStore.lockVibChoice() },
            set: { settingsStore.setLockVibChoice($0) }
        )
    }
}

// MARK: - 无感实时状态（日常精简版）
private struct KeylessRealtimeStatusHost: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    @ObservedObject private var backgroundExecution = BackgroundExecutionManager.shared

    @State private var decisionSnapshot = KeylessDecisionSnapshot.placeholder
    @State private var phoneNearbySince: Date?
    @State private var phoneFarAwaySince: Date?
    @State private var binding = VehicleBLEBindingStore.load()

    private var decisionContext: KeylessDecisionEngine.Context {
        KeylessDecisionEngine.Context(
            bleAuthenticated: connectionStatusStore.bleStatus == .authenticated || decisionSnapshot.hasCompletedBLEAuth,
            freshnessMaxAge: 90
        )
    }

    private var evaluationState: VehicleState {
        var state = decisionSnapshot.asVehicleState
        if let smoothed = diagnostics.debugSmoothedRSSI {
            state.bleRssi = smoothed
            state.phoneNearby = resolvedPhoneNearby(
                smoothed: smoothed,
                previous: state.phoneNearby,
                unlock: settingsStore.settings.unlockThreshold,
                lock: settingsStore.settings.lockThreshold
            )
        }
        return state
    }

    private var unlockDecision: KeylessDecision {
        // 启动电源模式时，主判定改为启动电源
        if settingsStore.settings.powerStartEnabled {
            return KeylessDecisionEngine.evaluatePowerStartWithDelay(
                state: evaluationState,
                settings: settingsStore.settings,
                phoneNearbySince: phoneNearbySince,
                context: decisionContext
            )
        }
        return KeylessDecisionEngine.evaluateUnlockWithDelay(
            state: evaluationState,
            settings: settingsStore.settings,
            phoneNearbySince: phoneNearbySince,
            context: decisionContext
        )
    }

    private var lockDecision: KeylessDecision {
        KeylessDecisionEngine.evaluateLockWithDelay(
            state: evaluationState,
            settings: settingsStore.settings,
            phoneFarAwaySince: phoneFarAwaySince,
            context: decisionContext
        )
    }

    private var lockDelayRemainingText: String {
        guard let farSince = phoneFarAwaySince else { return "--" }
        let delay = max(settingsStore.settings.lockDelay, 0)
        guard delay > 0 else { return "0s" }
        let elapsed = Date().timeIntervalSince(farSince)
        let remaining = max(0, Int(ceil(delay - elapsed)))
        return "\(remaining)s"
    }

    private var phaseText: String {
        let text = diagnostics.phaseText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "--" : text
    }

    private var signalText: String {
        if let smoothed = diagnostics.debugSmoothedRSSI {
            return "\(smoothed) dBm"
        }
        if let raw = diagnostics.debugRawRSSI {
            return "\(raw) dBm"
        }
        return "--"
    }

    private var approachLabel: String {
        settingsStore.settings.powerStartEnabled ? "靠近状态" : "手机距离"
    }

    private var primaryDecisionLabel: String {
        settingsStore.settings.powerStartEnabled ? "启动判定" : "解锁判定"
    }

    /// 围栏状态（中文短文案）
    private var geofenceStatusText: String {
        let settings = settingsStore.settings
        if !settings.keylessEnabled { return "随无感停用" }
        if !settings.geofenceWakeEnabled { return "未开启" }
        if backgroundExecution.phase == .degraded || backgroundExecution.lastLimitationReason?.contains("权限") == true {
            return "权限不足"
        }
        let hasVehicleCoord =
            VehicleLocationDisplayStore.shared.displayLatitudeGcj != 0
            && VehicleLocationDisplayStore.shared.displayLongitudeGcj != 0
        if !hasVehicleCoord { return "待就绪" }
        if backgroundExecution.isInGeofence { return "圈内 · 警戒" }
        if settings.scanOnlyInsideGeofence { return "圈外 · 暂停扫描" }
        return "圈外 · 休眠"
    }

    private var geofenceStatusColor: Color {
        switch geofenceStatusText {
        case "圈内 · 警戒": return AppTheme.green
        case "圈外 · 暂停扫描": return AppTheme.orange
        case "权限不足": return AppTheme.red
        case "待就绪": return AppTheme.orange
        case "未开启", "随无感停用": return Color.white.opacity(0.45)
        default: return Color.white.opacity(0.70)
        }
    }

    var body: some View {
        let state = evaluationState
        let unlockDecision = self.unlockDecision
        let lockDecision = self.lockDecision
        let phoneNearbyText = state.phoneNearby ? "已靠近" : "已远离"
        let showLockCountdown = lockDecision.actionTitle == "上锁" && lockDecision.logLevel == "等待"

        CardView(title: "无感实时状态", icon: "wave.3.right", iconColor: AppTheme.accent) {
            PopupInfoRowsView(
                rows: [
                    PopupInfoRowItem("wave.3.right", "当前阶段", phaseText, color: .white),
                    PopupInfoRowItem("location.circle", "围栏状态", geofenceStatusText, color: geofenceStatusColor),
                    PopupInfoRowItem("iphone.radiowaves.left.and.right", approachLabel, phoneNearbyText),
                    PopupInfoRowItem("dot.radiowaves.left.and.right", "信号", signalText, color: AppTheme.accent),
                    PopupInfoRowItem("lock.fill", "车锁状态", state.locked == true ? "已锁" : (state.locked == false ? "未锁" : "--")),
                    PopupInfoRowItem(
                        settingsStore.settings.powerStartEnabled ? "power.circle" : "lock.open.fill",
                        primaryDecisionLabel,
                        "\(unlockDecision.logLevel) · \(unlockDecision.reason)",
                        color: decisionColor(unlockDecision)
                    ),
                    PopupInfoRowItem("lock.fill", "上锁判定", "\(lockDecision.logLevel) · \(lockDecision.reason)", color: decisionColor(lockDecision)),
                    PopupInfoRowItem(
                        "timer",
                        "上锁倒计时",
                        showLockCountdown ? lockDelayRemainingText : "--",
                        color: AppTheme.orange
                    ),
                    PopupInfoRowItem(
                        "link",
                        "蓝牙绑定",
                        binding?.displaySummary ?? "尚未绑定",
                        mono: binding != nil,
                        color: binding == nil ? .secondary : AppTheme.green
                    )
                ],
                labelWidth: 74,
                valueLineLimit: nil,
                valueMinimumScaleFactor: 0.78,
                rowVerticalPadding: 8
            )

            if binding != nil {
                HStack(spacing: 10) {
                    SettingsActionButton(icon: "link.badge.minus", label: "取消绑定", color: AppTheme.red) {
                        VehicleBLEBindingStore.clear()
                        binding = nil
                        if let mqtt = VehicleStateStoreBridge.current as? MQTTVehicleStateStore {
                            mqtt.ensureBLESession(forceRestart: true, optimisticScanning: true, userInitiated: true)
                        }
                        VehicleEventLogStore.shared.add(.action, "清除蓝牙绑定", detail: "用户在无感页手动清除")
                    }
                }
            }
        }
        .onAppear {
            refreshDecisionInputs()
            binding = VehicleBLEBindingStore.load()
        }
        .onChange(of: diagnostics.debugLastSeenText) { _ in
            refreshDecisionInputs()
        }
        .onChange(of: diagnostics.debugLastTransitionText) { _ in
            refreshDecisionInputs()
        }
        .onChange(of: connectionStatusStore.bleStatus) { _ in
            refreshDecisionInputs()
            binding = VehicleBLEBindingStore.load()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if phoneNearbySince != nil || phoneFarAwaySince != nil {
                refreshDecisionInputs()
            }
        }
    }

    private func refreshDecisionInputs() {
        guard let mqtt = VehicleStateStoreBridge.current as? MQTTVehicleStateStore else { return }
        decisionSnapshot = KeylessDecisionSnapshot(from: mqtt)
        phoneNearbySince = mqtt.phoneNearbySince
        phoneFarAwaySince = mqtt.phoneFarAwaySince
        binding = VehicleBLEBindingStore.load()
    }

    private func resolvedPhoneNearby(smoothed: Int, previous: Bool, unlock: Double, lock: Double) -> Bool {
        if previous {
            return Double(smoothed) > lock
        }
        return Double(smoothed) >= unlock
    }

    private func decisionColor(_ decision: KeylessDecision) -> Color {
        switch decision {
        case .allow:
            return AppTheme.green
        case .deny:
            return AppTheme.red
        case .wait:
            return AppTheme.orange
        }
    }
}

/// 无感判定所需的最小车况快照，避免实时状态卡绑定整块 VehicleStateStore
private struct KeylessDecisionSnapshot: Equatable {
    var timestamp: Date
    var online: Bool
    var locked: Bool?
    var doorsClosed: Bool?
    var driverDoorOpen: Bool?
    var trunkOpen: Bool?
    var windowsClosed: Bool?
    var acOn: Bool?
    var acTemperature: Double?
    var gear: VehicleGear
    var power: VehiclePowerState
    var speed: Double?
    var physicalKeyPosition: PhysicalKeyPosition
    var bleRssi: Int?
    var phoneNearby: Bool
    var hasCompletedBLEAuth: Bool

    static let placeholder = KeylessDecisionSnapshot(
        timestamp: .distantPast,
        online: false,
        locked: nil,
        doorsClosed: nil,
        driverDoorOpen: nil,
        trunkOpen: nil,
        windowsClosed: nil,
        acOn: nil,
        acTemperature: nil,
        gear: .unknown,
        power: .unknown,
        speed: nil,
        physicalKeyPosition: .unknown,
        bleRssi: nil,
        phoneNearby: false,
        hasCompletedBLEAuth: false
    )

    init(
        timestamp: Date,
        online: Bool,
        locked: Bool?,
        doorsClosed: Bool?,
        driverDoorOpen: Bool?,
        trunkOpen: Bool?,
        windowsClosed: Bool?,
        acOn: Bool?,
        acTemperature: Double?,
        gear: VehicleGear,
        power: VehiclePowerState,
        speed: Double?,
        physicalKeyPosition: PhysicalKeyPosition,
        bleRssi: Int?,
        phoneNearby: Bool,
        hasCompletedBLEAuth: Bool
    ) {
        self.timestamp = timestamp
        self.online = online
        self.locked = locked
        self.doorsClosed = doorsClosed
        self.driverDoorOpen = driverDoorOpen
        self.trunkOpen = trunkOpen
        self.windowsClosed = windowsClosed
        self.acOn = acOn
        self.acTemperature = acTemperature
        self.gear = gear
        self.power = power
        self.speed = speed
        self.physicalKeyPosition = physicalKeyPosition
        self.bleRssi = bleRssi
        self.phoneNearby = phoneNearby
        self.hasCompletedBLEAuth = hasCompletedBLEAuth
    }

    init(from store: MQTTVehicleStateStore) {
        let state = store.state
        self.timestamp = state.timestamp
        self.online = state.online
        self.locked = state.locked
        self.doorsClosed = state.doorsClosed
        self.driverDoorOpen = state.driverDoorOpen
        self.trunkOpen = state.trunkOpen
        self.windowsClosed = state.windowsClosed
        self.acOn = state.acOn
        self.acTemperature = state.acTemperature
        self.gear = state.gear
        self.power = state.power
        self.speed = state.speed
        self.physicalKeyPosition = state.physicalKeyPosition
        self.bleRssi = state.bleRssi
        self.phoneNearby = state.phoneNearby
        self.hasCompletedBLEAuth = store.hasCompletedBLEAuth
    }

    var asVehicleState: VehicleState {
        VehicleState(
            timestamp: timestamp,
            online: online,
            locked: locked,
            doorsClosed: doorsClosed,
            driverDoorOpen: driverDoorOpen,
            trunkOpen: trunkOpen,
            windowsClosed: windowsClosed,
            acOn: acOn,
            acTemperature: acTemperature,
            gear: gear,
            power: power,
            speed: speed,
            physicalKeyPosition: physicalKeyPosition,
            bleRssi: bleRssi,
            phoneNearby: phoneNearby
        )
    }
}

// MARK: - 无感历史状态（摘要缓存）
private struct KeylessRecentActivitySection: View {
    @ObservedObject private var vehicleLog = VehicleEventLogStore.shared

    var body: some View {
        let summary = vehicleLog.keylessActivitySummary
        CardView(title: "无感历史状态", icon: "clock.arrow.circlepath", iconColor: AppTheme.purple) {
            PopupInfoRowsView(
                rows: [
                    PopupInfoRowItem("lock.open.fill", "最近解锁", summary.latestUnlock, color: AppTheme.green),
                    PopupInfoRowItem("lock.fill", "最近上锁", summary.latestLock, color: AppTheme.red),
                    PopupInfoRowItem("xmark.octagon.fill", "最近失败", summary.latestFailure, color: AppTheme.red),
                    PopupInfoRowItem("exclamationmark.triangle.fill", "最近拒绝", summary.latestReject, color: AppTheme.orange)
                ],
                labelWidth: 74,
                valueLineLimit: nil,
                valueMinimumScaleFactor: 0.78,
                rowVerticalPadding: 8
            )
        }
    }
}
