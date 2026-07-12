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
                KeylessBLEDiagnosticsHost()
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
        settingsStore.settings.pluginTakeover = (mode == .plugin)
        settingsStore.settings.smartSwitch = (mode == .smart)
        settingsStore.settings.appManual = (mode == .manual)

        let text: String
        switch mode {
        case .plugin: text = "插件托管"
        case .smart: text = "智能切换"
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

// MARK: - BLE 诊断宿主（最小依赖）
private struct KeylessBLEDiagnosticsHost: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    @ObservedObject private var bleKeyInfoStore = VehicleBLEKeyInfoStore.shared
    @ObservedObject private var credentialsStore = VehicleCredentialsStore.shared
    @State private var binding = VehicleBLEBindingStore.load()

    private var scanIntervalText: String {
        settingsStore.settings.bleScanInterval <= 0
            ? "无间隙"
            : "\(Int(settingsStore.settings.bleScanInterval))s"
    }

    private var cacheScopeText: String {
        let phone = credentialsStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let vin = credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneText = phone.isEmpty ? "--" : String(phone.suffix(4))
        let vinText = vin.isEmpty ? "--" : String(vin.suffix(6))
        return "phone=\(phoneText) · vin=\(vinText)"
    }

    private var bleKeySummaryText: String {
        let mac = bleKeyInfoStore.latestBleKeyInfo["bleMac"]
            ?? bleKeyInfoStore.latestBleKeyInfo["macAddress"]
            ?? "--"
        let keyId = bleKeyInfoStore.latestBleKeyInfo["keyId"] ?? "--"
        return "keyId=\(keyId) · mac=\(mac)"
    }

    private var rows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("wave.3.right", "当前阶段", diagnostics.phaseText, color: .white),
            PopupInfoRowItem("text.alignleft", "阶段详情", diagnostics.detailText, color: .white),
            PopupInfoRowItem("checkmark.circle", "最近结论", "\(diagnostics.lastConclusionText) · \(diagnostics.lastConclusionAtText)", color: AppTheme.green),
            PopupInfoRowItem("info.circle", "结论来源", diagnostics.lastReasonText, color: AppTheme.orange),
            PopupInfoRowItem("sum", "本次统计", diagnostics.countsSummaryText, color: AppTheme.orange),
            PopupInfoRowItem("timer", "扫描间隙", scanIntervalText, color: AppTheme.accent),
            PopupInfoRowItem("number", "连续超时", "\(diagnostics.consecutiveScanTimeouts)", color: AppTheme.orange),
            PopupInfoRowItem("person.text.rectangle", "当前作用域", cacheScopeText, mono: true, color: .white),
            PopupInfoRowItem("antenna.radiowaves.left.and.right", "当前BLE", bleKeySummaryText, mono: true, color: AppTheme.accent),
            PopupInfoRowItem("link", "蓝牙绑定", binding?.displaySummary ?? "尚未绑定", mono: binding != nil, color: binding == nil ? .secondary : AppTheme.green)
        ]
    }

    var body: some View {
        CardView(title: "BLE 诊断", icon: "wave.3.right.circle", iconColor: AppTheme.accent) {
            PopupInfoRowsView(
                rows: rows,
                labelWidth: 74,
                valueLineLimit: nil,
                valueMinimumScaleFactor: 0.78,
                rowVerticalPadding: 8
            )

            if binding != nil {
                HStack(spacing: 10) {
                    SettingsActionButton(icon: "link.badge.minus", label: "清除绑定", color: AppTheme.red) {
                        VehicleBLEBindingStore.clear()
                        binding = nil
                        if let mqtt = VehicleStateStoreBridge.current as? MQTTVehicleStateStore {
                            mqtt.ensureBLESession(forceRestart: true, optimisticScanning: true)
                        }
                        VehicleEventLogStore.shared.add(.action, "清除蓝牙绑定", detail: "用户在无感页手动清除")
                    }
                }
            }
        }
        .onAppear { binding = VehicleBLEBindingStore.load() }
    }
}

// MARK: - 无感实时状态宿主（最小依赖）
private struct KeylessRealtimeStatusHost: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared

    /// 只取判定需要的车况字段快照，不观察整块 vehicleStore 的 body 依赖链
    @State private var decisionSnapshot = KeylessDecisionSnapshot.placeholder
    @State private var phoneNearbySince: Date?
    @State private var phoneFarAwaySince: Date?

    private var modeText: String {
        guard settingsStore.settings.keylessEnabled else { return "无感关闭" }
        if settingsStore.settings.pluginTakeover { return "插件托管" }
        if settingsStore.settings.smartSwitch { return "智能切换" }
        if settingsStore.settings.appManual { return "前台手动" }
        return "未选择"
    }

    private var appExecEnabled: Bool {
        guard settingsStore.settings.keylessEnabled else { return false }
        if settingsStore.settings.pluginTakeover { return true }
        if settingsStore.settings.smartSwitch { return true }
        if settingsStore.settings.appManual { return false }
        return false
    }

    private var decisionContext: KeylessDecisionEngine.Context {
        KeylessDecisionEngine.Context(
            bleAuthenticated: connectionStatusStore.bleStatus == .authenticated || decisionSnapshot.hasCompletedBLEAuth,
            freshnessMaxAge: 90
        )
    }

    private var evaluationState: VehicleState {
        var state = decisionSnapshot.asVehicleState
        // 实时状态卡优先用 diagnostics 的 live RSSI，避免因 RSSI 数字变化去订阅整车 state
        if let smoothed = diagnostics.debugSmoothedRSSI {
            state.bleRssi = smoothed
            state.phoneNearby = resolvedPhoneNearby(
                smoothed: smoothed,
                previous: state.phoneNearby,
                unlock: settingsStore.settings.unlockThreshold,
                lock: settingsStore.settings.lockThreshold
            )
        } else if diagnostics.debugRawRSSI == nil {
            // 无 live 诊断时保留 snapshot 原值
        }
        return state
    }

    private var unlockDecision: KeylessDecision {
        KeylessDecisionEngine.evaluateUnlockWithDelay(
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

    var body: some View {
        let state = evaluationState
        let unlockThreshold = Int(settingsStore.settings.unlockThreshold)
        let lockThreshold = Int(settingsStore.settings.lockThreshold)
        let unlockDecision = self.unlockDecision
        let lockDecision = self.lockDecision
        let phoneNearbyText = state.phoneNearby ? "已靠近" : "已远离"

        CardView(title: "无感实时状态", icon: "wave.3.right", iconColor: AppTheme.accent) {
            PopupInfoRowsView(
                rows: [
                    PopupInfoRowItem("slider.horizontal.3", "当前模式", modeText),
                    PopupInfoRowItem("checkmark.shield", "App执行", appExecEnabled ? "允许" : "关闭", color: appExecEnabled ? AppTheme.green : AppTheme.orange),
                    PopupInfoRowItem("iphone.radiowaves.left.and.right", "手机距离", phoneNearbyText),
                    PopupInfoRowItem("dot.radiowaves.left.and.right", "平滑RSSI", diagnostics.debugSmoothedRSSI.map { "\($0) dBm" } ?? "--"),
                    PopupInfoRowItem("waveform.path.ecg", "原始RSSI", diagnostics.debugRawRSSI.map { "\($0) dBm" } ?? "--"),
                    PopupInfoRowItem("slider.horizontal.below.rectangle", "判定阈值", "unlock \(unlockThreshold) / lock \(lockThreshold) dBm", color: AppTheme.accent),
                    PopupInfoRowItem("clock.badge.checkmark", "最近RSSI", diagnostics.debugLastSeenText),
                    PopupInfoRowItem("arrow.left.arrow.right", "最近翻转", diagnostics.debugLastTransitionText, color: AppTheme.orange),
                    PopupInfoRowItem("lock.fill", "车锁状态", state.locked == true ? "已锁" : (state.locked == false ? "未锁" : "--")),
                    PopupInfoRowItem("lock.open.fill", "解锁判定", "\(unlockDecision.logLevel) · \(unlockDecision.reason)", color: decisionColor(unlockDecision)),
                    PopupInfoRowItem("lock.fill", "上锁判定", "\(lockDecision.logLevel) · \(lockDecision.reason)", color: decisionColor(lockDecision)),
                    PopupInfoRowItem("timer", "上锁倒计时", lockDecision.actionTitle == "上锁" && lockDecision.logLevel == "等待" ? lockDelayRemainingText : "--", color: AppTheme.orange)
                ],
                labelWidth: 74,
                valueLineLimit: nil,
                valueMinimumScaleFactor: 0.78,
                rowVerticalPadding: 8
            )

            HStack(spacing: 10) {
                SettingsActionButton(icon: "play.circle", label: "试算解锁", color: AppTheme.green) {
                    let detail = KeylessDecisionEngine.logDetail(decision: unlockDecision, state: state, settings: settingsStore.settings)
                    VehicleEventLogStore.shared.add(.keyless, "解锁试算", detail: detail)
                }
                SettingsActionButton(icon: "play.circle", label: "试算上锁", color: AppTheme.red) {
                    let detail = KeylessDecisionEngine.logDetail(decision: lockDecision, state: state, settings: settingsStore.settings)
                    VehicleEventLogStore.shared.add(.keyless, "上锁试算", detail: detail)
                }
            }
        }
        .onAppear {
            refreshDecisionInputs()
        }
        // diagnostics 更新时同步判定输入；不订阅整块 vehicleStore
        .onChange(of: diagnostics.debugLastSeenText) { _ in
            refreshDecisionInputs()
        }
        .onChange(of: diagnostics.debugLastTransitionText) { _ in
            refreshDecisionInputs()
        }
        .onChange(of: connectionStatusStore.bleStatus) { _ in
            refreshDecisionInputs()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            // 仅在延迟等待中才刷新倒计时数字
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
