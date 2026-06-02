import SwiftUI

// MARK: - Keyless View (Tab 2)
struct KeylessView: View {
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
    @State private var unlockVibPattern = VibrationPattern.shortSingle
    @State private var unlockVibStrength: Double = 60

    // 上锁
    @State private var lockEnabled = true
    @State private var lockThreshold: Double = -72
    @State private var lockDelay: Double = 15
    @State private var lockPopup = true
    @State private var lockVibrate = true
    @State private var lockVibPattern = VibrationPattern.shortSingle
    @State private var lockVibStrength: Double = 60

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    keylessSection    // 无感功能 — 最上面
                    unlockSection     // 解锁设置
                    lockSection       // 上锁设置
                    Spacer(minLength: 20)
                }
                .padding(.vertical, 16)
            }
            .background(AppBackgroundView().ignoresSafeArea())
            .navigationTitle("无感车控")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
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

                    // 弹窗在上
                    ToggleRow(icon: "bell.fill", label: "解锁弹窗", isOn: $unlockPopup)

                    // 震动在下
                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $unlockVibrate)

                    // 震动详情折叠
                    if unlockVibrate {
                        vibDetail(
                            pattern: $unlockVibPattern,
                            strength: $unlockVibStrength,
                            tint: AppTheme.green,
                            testLabel: "模拟解锁震动"
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
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

                    // 弹窗在上
                    ToggleRow(icon: "bell.fill", label: "上锁弹窗", isOn: $lockPopup)

                    // 震动在下
                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $lockVibrate)

                    if lockVibrate {
                        vibDetail(
                            pattern: $lockVibPattern,
                            strength: $lockVibStrength,
                            tint: AppTheme.red,
                            testLabel: "模拟上锁震动"
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Vibration Detail
    private func vibDetail(pattern: Binding<VibrationPattern>,
                           strength: Binding<Double>,
                           tint: Color,
                           testLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("震动模式")
                .font(.system(size: 12)).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VibrationPattern.allCases, id: \.self) { p in
                        ChipButton(text: p.rawValue, isSelected: pattern.wrappedValue == p) {
                            pattern.wrappedValue = p
                        }
                    }
                }
            }

            SliderRow(icon: "gauge.medium", label: "震动强度",
                      value: strength, range: 20...100, step: 1,
                      format: "\(Int(strength.wrappedValue))%", tint: tint)

            Button(action: {
                // 真实震动
                pattern.wrappedValue.play()
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
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
