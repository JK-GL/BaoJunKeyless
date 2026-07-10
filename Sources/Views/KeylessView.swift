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
    @EnvironmentObject var vehicleStore: VehicleStateStore

    @State private var showUnlockRecorder = false
    @State private var showLockRecorder = false

    private var mqttStore: MQTTVehicleStateStore? {
        vehicleStore as? MQTTVehicleStateStore
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "无感车控")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                KeylessMainSection(setMode: setMode)
                if let mqttStore {
                    KeylessBLEDiagnosticsSection(store: mqttStore, diagnostics: mqttStore.bleDiagnosticsStore)
                }
                if let mqttStore {
                    KeylessRealtimeStatusSection(
                        diagnostics: mqttStore.bleDiagnosticsStore,
                        modeText: currentModeText,
                        appExecEnabled: appExecutionEnabled,
                        state: vehicleStore.state,
                        unlockThreshold: Int(settingsStore.settings.unlockThreshold),
                        lockThreshold: Int(settingsStore.settings.lockThreshold),
                        unlockDecision: currentUnlockDecision,
                        lockDecision: currentLockDecision,
                        lockDelayRemainingText: lockDelayRemainingText,
                        onSimulateUnlock: simulateUnlockDecision,
                        onSimulateLock: simulateLockDecision
                    )
                }
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

    private var currentModeText: String {
        guard settingsStore.settings.keylessEnabled else { return "无感关闭" }
        if settingsStore.settings.pluginTakeover { return "插件托管" }
        if settingsStore.settings.smartSwitch { return "智能切换" }
        if settingsStore.settings.appManual { return "前台手动" }
        return "未选择"
    }

    private var appExecutionEnabled: Bool {
        guard settingsStore.settings.keylessEnabled else { return false }
        if settingsStore.settings.pluginTakeover { return true }
        if settingsStore.settings.smartSwitch { return true }
        if settingsStore.settings.appManual { return false }
        return false
    }

    private var currentUnlockDecision: KeylessDecision {
        KeylessDecisionEngine.evaluateUnlockWithDelay(
            state: vehicleStore.state,
            settings: settingsStore.settings,
            phoneNearbySince: mqttStore?.phoneNearbySince
        )
    }

    private var currentLockDecision: KeylessDecision {
        KeylessDecisionEngine.evaluateLockWithDelay(
            state: vehicleStore.state,
            settings: settingsStore.settings,
            phoneFarAwaySince: mqttStore?.phoneFarAwaySince
        )
    }

    private var lockDelayRemainingText: String {
        guard let farSince = mqttStore?.phoneFarAwaySince else { return "--" }
        let delay = max(settingsStore.settings.lockDelay, 0)
        guard delay > 0 else { return "0s" }
        let elapsed = Date().timeIntervalSince(farSince)
        let remaining = max(0, Int(ceil(delay - elapsed)))
        return "\(remaining)s"
    }

    private func simulateUnlockDecision() {
        let decision = currentUnlockDecision
        let detail = KeylessDecisionEngine.logDetail(decision: decision, state: vehicleStore.state, settings: settingsStore.settings)
        VehicleEventLogStore.shared.add(.keyless, "解锁试算", detail: detail)
    }

    private func simulateLockDecision() {
        let decision = currentLockDecision
        let detail = KeylessDecisionEngine.logDetail(decision: decision, state: vehicleStore.state, settings: settingsStore.settings)
        VehicleEventLogStore.shared.add(.keyless, "上锁试算", detail: detail)
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

private struct KeylessBLEDiagnosticsSection: View {
    let store: MQTTVehicleStateStore
    @ObservedObject var diagnostics: BLEDiagnosticsStore
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    @ObservedObject private var bleKeyInfoStore = VehicleBLEKeyInfoStore.shared
    @State private var binding = VehicleBLEBindingStore.load()

    private var rows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("dot.radiowaves.left.and.right", "BLE状态", bleStatusText(connectionStatusStore.bleStatus), color: AppTheme.accent),
            PopupInfoRowItem("wave.3.right", "当前阶段", diagnostics.phaseText, color: .white),
            PopupInfoRowItem("text.alignleft", "阶段详情", diagnostics.detailText, color: .white),
            PopupInfoRowItem("checkmark.circle", "最近结论", "\(diagnostics.lastConclusionText) · \(diagnostics.lastConclusionAtText)", color: AppTheme.green),
            PopupInfoRowItem("info.circle", "结论来源", diagnostics.lastReasonText, color: AppTheme.orange),
            PopupInfoRowItem("sum", "本次统计", diagnostics.countsSummaryText, color: AppTheme.orange),
            PopupInfoRowItem("timer", "扫描间隙", store.keylessSettingsStore.settings.bleScanInterval <= 0 ? "无间隙" : "\(Int(store.keylessSettingsStore.settings.bleScanInterval))s", color: AppTheme.accent),
            PopupInfoRowItem("number", "连续超时", "\(store.consecutiveScanTimeouts)", color: AppTheme.orange),
            PopupInfoRowItem("person.text.rectangle", "当前作用域", cacheScopeText(), mono: true, color: .white),
            PopupInfoRowItem("antenna.radiowaves.left.and.right", "当前BLE", bleKeySummaryText(), mono: true, color: AppTheme.accent),
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

            Text("本次统计 = 本次运行累计结果；重开 App 后会重新开始累计。")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if binding != nil {
                HStack(spacing: 10) {
                    SettingsActionButton(icon: "link.badge.minus", label: "清除绑定", color: AppTheme.red) {
                        VehicleBLEBindingStore.clear()
                        binding = nil
                        store.ensureBLESession(forceRestart: true, optimisticScanning: true)
                        VehicleEventLogStore.shared.add(.action, "清除蓝牙绑定", detail: "用户在无感页手动清除")
                    }
                }
            }
        }
        .onAppear { binding = VehicleBLEBindingStore.load() }
    }

    private func bleStatusText(_ status: VehicleConnectionStatusStore.LiveBLEStatus) -> String {
        switch status {
        case .disconnected: return "未连接"
        case .scanning: return "扫描中"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .authenticating: return "鉴权中"
        case .authenticated: return "已连接"
        case .error: return "异常"
        }
    }

    private func cacheScopeText() -> String {
        let phone = store.credentialsStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let vin = store.credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneText = phone.isEmpty ? "--" : String(phone.suffix(4))
        let vinText = vin.isEmpty ? "--" : String(vin.suffix(6))
        return "phone=\(phoneText) · vin=\(vinText)"
    }

    private func bleKeySummaryText() -> String {
        let mac = bleKeyInfoStore.latestBleKeyInfo["bleMac"] ?? bleKeyInfoStore.latestBleKeyInfo["macAddress"] ?? "--"
        let keyId = bleKeyInfoStore.latestBleKeyInfo["keyId"] ?? "--"
        return "keyId=\(keyId) · mac=\(mac)"
    }
}

private struct KeylessRealtimeStatusSection: View {
    @ObservedObject var diagnostics: BLEDiagnosticsStore
    let modeText: String
    let appExecEnabled: Bool
    let state: VehicleState
    let unlockThreshold: Int
    let lockThreshold: Int
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
                    PopupInfoRowItem("dot.radiowaves.left.and.right", "平滑RSSI", (diagnostics.debugSmoothedRSSI ?? state.bleRssi).map { "\($0) dBm" } ?? "--"),
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

private struct KeylessRecentActivitySection: View {
    @ObservedObject private var vehicleLog = VehicleEventLogStore.shared

    var body: some View {
        CardView(title: "无感历史状态", icon: "clock.arrow.circlepath", iconColor: AppTheme.purple) {
            PopupInfoRowsView(
                rows: [
                    PopupInfoRowItem("lock.open.fill", "最近解锁", latestUnlockText, color: AppTheme.green),
                    PopupInfoRowItem("lock.fill", "最近上锁", latestLockText, color: AppTheme.red),
                    PopupInfoRowItem("xmark.octagon.fill", "最近失败", latestFailureText, color: AppTheme.red),
                    PopupInfoRowItem("exclamationmark.triangle.fill", "最近拒绝", latestRejectText, color: AppTheme.orange)
                ],
                labelWidth: 74,
                valueLineLimit: nil,
                valueMinimumScaleFactor: 0.78,
                rowVerticalPadding: 8
            )
        }
    }

    private var latestUnlockText: String {
        latestDetail(titles: ["无感命令结果", "无感命令发送"], keyword: "解锁")
    }

    private var latestLockText: String {
        latestDetail(titles: ["无感命令结果", "无感命令发送"], keyword: "上锁")
    }

    private var latestFailureText: String {
        latestDetail(categories: [.error], titles: ["无感命令结果"], keyword: "无感")
    }

    private var latestRejectText: String {
        latestDetail(titles: ["解锁拒绝", "上锁拒绝"])
    }

    private func latestDetail(
        categories: Set<VehicleEventLogCategory>? = nil,
        titles: [String],
        keyword: String? = nil
    ) -> String {
        for entry in vehicleLog.todayEntries {
            if let categories, !categories.contains(entry.category) { continue }
            if !titles.contains(entry.title) { continue }
            if let keyword {
                let haystack = entry.detail + " " + entry.title
                if !haystack.localizedCaseInsensitiveContains(keyword) { continue }
            }
            return entry.detail.isEmpty ? entry.timeText : "\(entry.timeText) · \(entry.detail)"
        }
        return "--"
    }
}
