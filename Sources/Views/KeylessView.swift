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
    @ObservedObject private var decisionDisplayStore = KeylessDecisionDisplayStore.shared

    private var decisionSnapshot: KeylessDecisionDisplaySnapshot {
        decisionDisplayStore.snapshot
    }
    private var phoneNearbySince: Date? {
        decisionSnapshot.phoneNearbySince
    }
    private var phoneFarAwaySince: Date? {
        decisionSnapshot.phoneFarAwaySince
    }
    @State private var displayClock = Date()
    /// 上次鉴权成功的 BLE（软缓存展示，不是可取消绑定）
    @State private var lastVehicleSummary: String = "尚未连接过"

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
        let elapsed = displayClock.timeIntervalSince(farSince)
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
        // 与 BLE 胶囊 / 当前阶段统一：仅围栏内扫描开启时用「围栏外 · 休眠」
        if settings.scanOnlyInsideGeofence { return "围栏外 · 休眠" }
        return "圈外 · 待机"
    }

    private var geofenceStatusColor: Color {
        switch geofenceStatusText {
        case "圈内 · 警戒": return AppTheme.green
        case "围栏外 · 休眠": return AppTheme.orange
        case "权限不足": return AppTheme.red
        case "待就绪": return AppTheme.orange
        case "未开启", "随无感停用": return Color.white.opacity(0.45)
        default: return Color.white.opacity(0.70)
        }
    }

    /// 围栏摘要数据行：半径 · 距圆心（圈内外由围栏状态表达）
    private var geofenceMetricsDisplay: String {
        let text = backgroundExecution.geofenceMetricsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "--" : text
    }

    /// 圆心地址；空则隐藏副行
    private var geofenceAddressDisplay: String {
        backgroundExecution.geofenceCenterAddress.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    PopupInfoRowItem(
                        "mappin.and.ellipse",
                        "围栏摘要",
                        geofenceMetricsDisplay,
                        secondaryValue: geofenceAddressDisplay,
                        color: Color.white.opacity(0.82),
                        secondaryColor: Color.white.opacity(0.45)
                    ),
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
                        "antenna.radiowaves.left.and.right",
                        "上次连接",
                        lastVehicleSummary,
                        mono: lastVehicleSummary != "尚未连接过",
                        color: lastVehicleSummary == "尚未连接过" ? .secondary : AppTheme.green
                    )
                ],
                labelWidth: 68,
                // 主值尽量单行；地址走 secondary，避免整卡上下被长文撑开
                valueLineLimit: 1,
                secondaryLineLimit: 2,
                valueMinimumScaleFactor: 0.72,
                rowVerticalPadding: 5,
                labelFontSize: 12,
                valueFontSize: 12,
                secondaryFontSize: 10,
                iconSize: 12
            )

            }
        .onAppear {
            refreshLastVehicleSummary()
        }
        .onChange(of: diagnostics.debugLastSeenText) { _ in
            refreshLastVehicleSummary()
        }
        .onChange(of: diagnostics.debugLastTransitionText) { _ in
            refreshLastVehicleSummary()
        }
        .onChange(of: connectionStatusStore.bleStatus) { _ in
            refreshLastVehicleSummary()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { now in
            // 仅展示倒计时活跃时刷新本卡；不读取/不发布主车辆状态。
            if phoneNearbySince != nil || phoneFarAwaySince != nil {
                displayClock = now
            }
        }
    }

    private func refreshLastVehicleSummary() {
        guard let mqtt = VehicleStateStoreBridge.current as? MQTTVehicleStateStore else { return }
        let info = mqtt.latestBleKeyInfo
        let mac = info["bleMac"] ?? info["macAddress"] ?? ""
        let keyId = info["keyId"] ?? ""
        if let last = VehicleBLEManager.loadSoftLastVehicle(bleMac: mac, keyId: keyId) {
            lastVehicleSummary = last.displaySummary
        } else if !mac.isEmpty {
            lastVehicleSummary = "钥匙 \(mac) · 尚未缓存连接"
        } else {
            lastVehicleSummary = "尚未连接过"
        }
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
