import SwiftUI

// MARK: - 震动选择类型
enum VibrationChoice: Hashable {
    case preset(VibrationPattern)
    case custom(UUID)
}

struct KeylessView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var customStore: CustomVibrationStore
    @EnvironmentObject var vehicleLog: VehicleEventLogStore
    @EnvironmentObject var vehicleStore: VehicleStateStore

    @State private var showUnlockRecorder = false
    @State private var keylessPhoneFarAwaySince: Date? = nil
    @State private var showLockRecorder = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "无感车控")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                KeylessMainSection(setMode: setMode)
                KeylessRealtimeStatusSection(
                    modeText: currentModeText,
                    appExecEnabled: appExecutionEnabled,
                    state: vehicleStore.state,
                    unlockDecision: currentUnlockDecision,
                    lockDecision: currentLockDecision,
                    lockDelayRemainingText: lockDelayRemainingText,
                    onSimulateUnlock: simulateUnlockDecision,
                    onSimulateLock: simulateLockDecision
                )
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
                vehicleLog.add(.keyless, "录制解锁震动", detail: pattern.name)
            }
        }
        .sheet(isPresented: $showLockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setLockVibChoice(.custom(pattern.id))
                vehicleLog.add(.keyless, "录制上锁震动", detail: pattern.name)
            }
        }
        .onAppear(perform: syncKeylessPhoneDistanceState)
        .onChange(of: vehicleStore.state.phoneFarAway) { _ in
            syncKeylessPhoneDistanceState()
        }
    }

    private func syncKeylessPhoneDistanceState() {
        if vehicleStore.state.phoneFarAway {
            if keylessPhoneFarAwaySince == nil {
                keylessPhoneFarAwaySince = Date()
            }
        } else {
            keylessPhoneFarAwaySince = nil
        }
    }

    private var currentModeText: String {
        if settingsStore.settings.pluginTakeover { return "插件托管" }
        if settingsStore.settings.smartSwitch { return "智能切换" }
        if settingsStore.settings.appManual { return "App手动" }
        return "未选择"
    }

    private var appExecutionEnabled: Bool {
        !settingsStore.settings.pluginTakeover && (settingsStore.settings.smartSwitch || settingsStore.settings.appManual)
    }

    private var currentUnlockDecision: KeylessDecision {
        KeylessDecisionEngine.evaluateUnlock(state: vehicleStore.state, settings: settingsStore.settings)
    }

    private var currentLockDecision: KeylessDecision {
        KeylessDecisionEngine.evaluateLockWithDelay(state: vehicleStore.state, settings: settingsStore.settings, phoneFarAwaySince: keylessPhoneFarAwaySince)
    }

    private var lockDelayRemainingText: String {
        guard let farSince = keylessPhoneFarAwaySince else { return "--" }
        let delay = max(settingsStore.settings.lockDelay, 0)
        guard delay > 0 else { return "0s" }
        let elapsed = Date().timeIntervalSince(farSince)
        let remaining = max(0, Int(ceil(delay - elapsed)))
        return "\(remaining)s"
    }

    private func simulateUnlockDecision() {
        let decision = currentUnlockDecision
        let detail = KeylessDecisionEngine.logDetail(decision: decision, state: vehicleStore.state, settings: settingsStore.settings)
        vehicleLog.add(.keyless, "解锁试算", detail: detail)
    }

    private func simulateLockDecision() {
        let decision = currentLockDecision
        let detail = KeylessDecisionEngine.logDetail(decision: decision, state: vehicleStore.state, settings: settingsStore.settings)
        vehicleLog.add(.keyless, "上锁试算", detail: detail)
    }

    private func setMode(_ mode: KeylessControlMode) {
        settingsStore.settings.pluginTakeover = (mode == .plugin)
        settingsStore.settings.smartSwitch = (mode == .smart)
        settingsStore.settings.appManual = (mode == .manual)

        let text: String
        switch mode {
        case .plugin: text = "插件托管"
        case .smart: text = "智能切换"
        case .manual: text = "App 手动"
        }
        vehicleLog.add(.keyless, "切换无感模式", detail: text)
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

private struct KeylessRealtimeStatusSection: View {
    let modeText: String
    let appExecEnabled: Bool
    let state: VehicleState
    let unlockDecision: KeylessDecision
    let lockDecision: KeylessDecision
    let lockDelayRemainingText: String
    let onSimulateUnlock: () -> Void
    let onSimulateLock: () -> Void

    var body: some View {
        CardView(title: "无感实时状态", icon: "wave.3.right", iconColor: AppTheme.accent) {
            PopupInfoRowsView(
                rows: [
                    PopupInfoRowItem("slider.horizontal.3", "当前模式", modeText),
                    PopupInfoRowItem("checkmark.shield", "App执行", appExecEnabled ? "允许" : "关闭", color: appExecEnabled ? AppTheme.green : AppTheme.orange),
                    PopupInfoRowItem("iphone.radiowaves.left.and.right", "手机距离", state.phoneNearby ? "已靠近" : "已远离"),
                    PopupInfoRowItem("dot.radiowaves.left.and.right", "蓝牙RSSI", state.bleRssi.map { "\($0) dBm" } ?? "--"),
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
                SettingsActionButton(icon: "play.circle", label: "试算解锁", color: AppTheme.green, action: onSimulateUnlock)
                SettingsActionButton(icon: "play.circle", label: "试算上锁", color: AppTheme.red, action: onSimulateLock)
            }
        }
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
