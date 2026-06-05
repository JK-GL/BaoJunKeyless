import SwiftUI

struct KeylessMainSection: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    let setMode: (KeylessControlMode) -> Void

    var body: some View {
        CardView(title: "无感功能", icon: "dot.radiowaves.left.and.right", iconColor: AppTheme.purple) {
            ToggleRow(icon: "power", label: "无感开关", isOn: $settingsStore.settings.keylessEnabled)

            if settingsStore.settings.keylessEnabled {
                VStack(spacing: 12) {
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
}

struct UnlockSettingsSection: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @Binding var showRecorder: Bool
    let choice: Binding<VibrationChoice>
    let customStore: CustomVibrationStore

    var body: some View {
        CardView(title: "解锁设置", icon: "lock.open.fill", iconColor: AppTheme.green) {
            ToggleRow(icon: "power", label: "解锁开关", isOn: $settingsStore.settings.unlockEnabled)

            if settingsStore.settings.unlockEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $settingsStore.settings.unlockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(settingsStore.settings.unlockThreshold)) dBm", tint: AppTheme.green)

                    ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $settingsStore.settings.unlockVibrate)

                    if settingsStore.settings.unlockVibrate {
                        VibrationSettingsDetail(
                            choice: choice,
                            strength: $settingsStore.settings.unlockVibStrength,
                            tint: AppTheme.green,
                            testLabel: "模拟解锁震动",
                            showRecorder: $showRecorder,
                            customStore: customStore
                        )
                    }

                    ToggleRow(icon: "bell.fill", label: "解锁弹窗", isOn: $settingsStore.settings.unlockPopup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct LockSettingsSection: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @Binding var showRecorder: Bool
    let choice: Binding<VibrationChoice>
    let customStore: CustomVibrationStore

    var body: some View {
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
                        VibrationSettingsDetail(
                            choice: choice,
                            strength: $settingsStore.settings.lockVibStrength,
                            tint: AppTheme.red,
                            testLabel: "模拟上锁震动",
                            showRecorder: $showRecorder,
                            customStore: customStore
                        )
                    }

                    ToggleRow(icon: "bell.fill", label: "上锁弹窗", isOn: $settingsStore.settings.lockPopup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct VibrationSettingsDetail: View {
    @EnvironmentObject var theme: ThemeManager
    let choice: Binding<VibrationChoice>
    let strength: Binding<Double>
    let tint: Color
    let testLabel: String
    @Binding var showRecorder: Bool
    let customStore: CustomVibrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预设模式")
                .font(.system(size: 12)).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VibrationPattern.allCases, id: \.self) { pattern in
                        let isSelected: Bool = {
                            if case .preset(let value) = choice.wrappedValue, value == pattern { return true }
                            return false
                        }()
                        ChipButton(text: pattern.rawValue, isSelected: isSelected) {
                            choice.wrappedValue = .preset(pattern)
                        }
                    }
                }
            }

            if !customStore.patterns.isEmpty {
                HStack {
                    Text("自定义模式")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(customStore.patterns) { pattern in
                            let isSelected: Bool = {
                                if case .custom(let id) = choice.wrappedValue, id == pattern.id { return true }
                                return false
                            }()
                            HStack(spacing: 4) {
                                ChipButton(text: pattern.name, isSelected: isSelected) {
                                    choice.wrappedValue = .custom(pattern.id)
                                }
                                Button(action: { customStore.delete(pattern) }) {
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

            Button(action: { showRecorder = true }) {
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

            SliderRow(icon: "gauge.medium", label: "震动强度",
                      value: strength, range: 20...100, step: 1,
                      format: "\(Int(strength.wrappedValue))%", tint: tint)

            Button(action: {
                switch choice.wrappedValue {
                case .preset(let pattern):
                    pattern.play(intensity: strength.wrappedValue / 100.0)
                case .custom(let id):
                    if let pattern = customStore.patterns.first(where: { $0.id == id }) {
                        pattern.play(intensity: strength.wrappedValue / 100.0)
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

enum KeylessControlMode {
    case plugin
    case smart
    case manual
}
