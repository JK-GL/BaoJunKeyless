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
    @StateObject private var customStore = CustomVibrationStore()

    // 无感功能
    @State private var keylessEnabled = true
    @State private var pluginTakeover = true
    @State private var smartSwitch = false
    @State private var drBlock = false
    @State private var cmdInterval: Double = 5

    // 解锁
    @State private var unlockEnabled = true
    @State private var unlockThreshold: Double = -48
    @State private var unlockPopup = true
    @State private var unlockVibrate = true
    @State private var unlockVibChoice: VibrationChoice = .preset(.shortSingle)
    @State private var unlockVibStrength: Double = 60
    @State private var showUnlockRecorder = false

    // 上锁
    @State private var lockEnabled = true
    @State private var lockThreshold: Double = -72
    @State private var lockDelay: Double = 15
    @State private var lockPopup = true
    @State private var lockVibrate = true
    @State private var lockVibChoice: VibrationChoice = .preset(.shortSingle)
    @State private var lockVibStrength: Double = 60
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
            ToggleRow(icon: "power",                           label: "无感开关",    isOn: $keylessEnabled)
            ToggleRow(icon: "shield.fill",                     label: "插件托管",    isOn: $pluginTakeover)
            ToggleRow(icon: "arrow.triangle.2.circlepath",     label: "智能切换",    isOn: $smartSwitch)
            ToggleRow(icon: "exclamationmark.triangle.fill",   label: "D/R 挡禁止", isOn: $drBlock)
            SliderRow(icon: "gauge.medium", label: "重复指令间隔",
                      value: $cmdInterval, range: 1...15, step: 1,
                      format: "\(Int(cmdInterval))s", tint: AppTheme.purple)
        }
    }

    // MARK: 解锁设置
    private var unlockSection: some View {
        CardView(title: "解锁设置", icon: "lock.open.fill", iconColor: AppTheme.green) {
            // 主开关
            ToggleRow(icon: "power", label: "解锁开关", isOn: $unlockEnabled)

            // 折叠区域
            if unlockEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $unlockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(unlockThreshold)) dBm", tint: AppTheme.green)

                    // 震动在上
                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $unlockVibrate)

                    // 震动详情折叠
                    if unlockVibrate {
                        vibDetail(
                            choice: $unlockVibChoice,
                            strength: $unlockVibStrength,
                            tint: AppTheme.green,
                            testLabel: "模拟解锁震动",
                            showRecorder: $showUnlockRecorder,
                            customStore: customStore
                        )
                    }

                    // 弹窗在最后
                    ToggleRow(icon: "bell.fill", label: "解锁弹窗", isOn: $unlockPopup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showUnlockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                unlockVibChoice = .custom(pattern.id)
            }
        }
    }

    // MARK: 上锁设置
    private var lockSection: some View {
        CardView(title: "上锁设置", icon: "lock.fill", iconColor: AppTheme.red) {
            ToggleRow(icon: "power", label: "上锁开关", isOn: $lockEnabled)

            if lockEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $lockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(lockThreshold)) dBm", tint: AppTheme.red)

                    SliderRow(icon: "gauge.medium", label: "上锁延迟",
                              value: $lockDelay, range: 0...60, step: 1,
                              format: "\(Int(lockDelay))s", tint: AppTheme.red)

                    // 震动在上
                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $lockVibrate)

                    if lockVibrate {
                        vibDetail(
                            choice: $lockVibChoice,
                            strength: $lockVibStrength,
                            tint: AppTheme.red,
                            testLabel: "模拟上锁震动",
                            showRecorder: $showLockRecorder,
                            customStore: customStore
                        )
                    }

                    // 弹窗在最后
                    ToggleRow(icon: "bell.fill", label: "上锁弹窗", isOn: $lockPopup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showLockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                lockVibChoice = .custom(pattern.id)
            }
        }
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
                        cp.play()
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
