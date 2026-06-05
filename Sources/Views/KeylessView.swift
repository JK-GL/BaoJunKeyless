import SwiftUI

// MARK: - 震动选择类型
enum VibrationChoice: Hashable {
    case preset(VibrationPattern)
    case custom(UUID)
}

// MARK: - Keyless View (Tab 2)
struct KeylessView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @StateObject private var customStore = CustomVibrationStore()

    // 仅用于 UI 状态（不持久化）
    @State private var showUnlockRecorder = false
    @State private var showLockRecorder = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "无感车控")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                keylessSection
                unlockSection
                lockSection

                Spacer(minLength: 100)
            }
        }
        .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
        .onDisappear {
            scrollState.reset()
        }
    }

    // MARK: 无感功能
    private var keylessSection: some View {
        CardView(title: "无感功能", icon: "dot.radiowaves.left.and.right", iconColor: AppTheme.purple) {
            // 主开关
            ToggleRow(icon: "power", label: "无感开关", isOn: $settingsStore.settings.keylessEnabled)

            // 折叠区域
            if settingsStore.settings.keylessEnabled {
                VStack(spacing: 12) {
                    // 三选一互斥
                    ToggleRow(icon: "shield.fill", label: "插件托管", isOn: Binding(
                        get: { settingsStore.settings.pluginTakeover },
                        set: { if $0 { setMode(.plugin) } else { settingsStore.settings.pluginTakeover = false } }
                    ))
                    ToggleRow(icon: "arrow.triangle.2.circlepath", label: "智能切换", isOn: Binding(
                        get: { settingsStore.settings.smartSwitch },
                        set: { if $0 { setMode(.smart) } else { settingsStore.settings.smartSwitch = false } }
                    ))
                    ToggleRow(icon: "iphone", label: "App 手动", isOn: Binding(
                        get: { settingsStore.settings.appManual },
                        set: { if $0 { setMode(.manual) } else { settingsStore.settings.appManual = false } }
                    ))

                    ToggleRow(icon: "exclamationmark.triangle.fill", label: "D/R 挡禁止", isOn: $settingsStore.settings.drBlock)
                    SliderRow(icon: "gauge.medium", label: "重复指令间隔",
                              value: $settingsStore.settings.cmdInterval, range: 1...15, step: 1,
                              format: "\(Int(settingsStore.settings.cmdInterval))s", tint: AppTheme.purple)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: 模式切换（互斥）
    private enum ControlMode { case plugin, smart, manual }

    private func setMode(_ mode: ControlMode) {
        settingsStore.settings.pluginTakeover = (mode == .plugin)
        settingsStore.settings.smartSwitch = (mode == .smart)
        settingsStore.settings.appManual = (mode == .manual)
    }

    // MARK: 解锁设置
    private var unlockSection: some View {
        CardView(title: "解锁设置", icon: "lock.open.fill", iconColor: AppTheme.green) {
            ToggleRow(icon: "power", label: "解锁开关", isOn: $settingsStore.settings.unlockEnabled)

            if settingsStore.settings.unlockEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $settingsStore.settings.unlockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(settingsStore.settings.unlockThreshold)) dBm", tint: AppTheme.green)

                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $settingsStore.settings.unlockVibrate)

                    if settingsStore.settings.unlockVibrate {
                        vibDetail(
                            choice: unlockVibChoiceBinding,
                            strength: $settingsStore.settings.unlockVibStrength,
                            tint: AppTheme.green,
                            testLabel: "模拟解锁震动",
                            showRecorder: $showUnlockRecorder,
                            customStore: customStore
                        )
                    }

                    ToggleRow(icon: "bell.fill", label: "解锁弹窗", isOn: $settingsStore.settings.unlockPopup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showUnlockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setUnlockVibChoice(.custom(pattern.id))
            }
        }
    }

    // MARK: 上锁设置
    private var lockSection: some View {
        CardView(title: "上锁设置", icon: "lock.fill", iconColor: AppTheme.red) {
            ToggleRow(icon: "power", label: "上锁开关", isOn: $settingsStore.settings.lockEnabled)

            if settingsStore.settings.lockEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $settingsStore.settings.lockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(settingsStore.settings.lockThreshold)) dBm", tint: AppTheme.red)

                    SliderRow(icon: "gauge.medium", label: "上锁延迟",
                              value: $settingsStore.settings.lockDelay, range: 0...60, step: 1,
                              format: "\(Int(settingsStore.settings.lockDelay))s", tint: AppTheme.red)

                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $settingsStore.settings.lockVibrate)

                    if settingsStore.settings.lockVibrate {
                        vibDetail(
                            choice: lockVibChoiceBinding,
                            strength: $settingsStore.settings.lockVibStrength,
                            tint: AppTheme.red,
                            testLabel: "模拟上锁震动",
                            showRecorder: $showLockRecorder,
                            customStore: customStore
                        )
                    }

                    ToggleRow(icon: "bell.fill", label: "上锁弹窗", isOn: $settingsStore.settings.lockPopup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showLockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setLockVibChoice(.custom(pattern.id))
            }
        }
    }

    // MARK: - 震动选择 Binding 桥接

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

    // MARK: Vibration Detail
    private func vibDetail(choice: Binding<VibrationChoice>,
                           strength: Binding<Double>,
                           tint: Color,
                           testLabel: String,
                           showRecorder: Binding<Bool>,
                           customStore: CustomVibrationStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 预设模式
            Text("预设模式")
                .font(.system(size: 12)).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VibrationPattern.allCases, id: \.self) { p in
                        let isSelected: Bool = {
                            if case .preset(let v) = choice.wrappedValue, v == p { return true }
                            return false
                        }()
                        ChipButton(text: p.rawValue, isSelected: isSelected) {
                            choice.wrappedValue = .preset(p)
                        }
                    }
                }
            }

            // 自定义模式
            if !customStore.patterns.isEmpty {
                HStack {
                    Text("自定义模式")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(customStore.patterns) { cp in
                            let isSelected: Bool = {
                                if case .custom(let id) = choice.wrappedValue, id == cp.id { return true }
                                return false
                            }()
                            HStack(spacing: 4) {
                                ChipButton(text: cp.name, isSelected: isSelected) {
                                    choice.wrappedValue = .custom(cp.id)
                                }
                                Button(action: { customStore.delete(cp) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.white.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // 录制新震动按钮
            Button(action: { showRecorder.wrappedValue = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13))
                    Text("录制新震动")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(tint.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // 强度滑块
            SliderRow(icon: "gauge.medium", label: "震动强度",
                      value: strength, range: 20...100, step: 1,
                      format: "\(Int(strength.wrappedValue))%", tint: tint)

            // 测试按钮
            Button(action: {
                switch choice.wrappedValue {
                case .preset(let p):
                    p.play(intensity: strength.wrappedValue / 100.0)
                case .custom(let id):
                    if let cp = customStore.patterns.first(where: { $0.id == id }) {
                        cp.play(intensity: strength.wrappedValue / 100.0)
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                    Text(testLabel)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(theme.cardStroke, lineWidth: 1)
                )
        )
    }
}
