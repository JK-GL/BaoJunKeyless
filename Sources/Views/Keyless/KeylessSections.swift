import SwiftUI

struct KeylessMainSection: View {
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    let setMode: (KeylessControlMode) -> Void

    var body: some View {
        CardView(title: "无感功能", icon: "dot.radiowaves.left.and.right", iconColor: AppTheme.purple) {
            ToggleRow(icon: "power", label: "无感开关", isOn: Binding(
                get: { settingsStore.settings.keylessEnabled },
                set: { enabled in
                    settingsStore.settings.keylessEnabled = enabled
                    VehicleEventLogStore.shared.add(.keyless, enabled ? "开启无感开关" : "关闭无感开关")
                }
            ))

            if settingsStore.settings.keylessEnabled {
                VStack(spacing: 12) {
                    ToggleRow(icon: "puzzlepiece", label: "插件托管", isOn: Binding(
                        get: { settingsStore.settings.pluginTakeover },
                        set: { if $0 { setMode(.plugin) } else { settingsStore.settings.pluginTakeover = false; VehicleEventLogStore.shared.add(.keyless, "关闭插件托管") } }
                    ))
                    ToggleRow(icon: "iphone", label: "前台手动", isOn: Binding(
                        get: { settingsStore.settings.appManual },
                        set: { if $0 { setMode(.manual) } else { settingsStore.settings.appManual = false; VehicleEventLogStore.shared.add(.keyless, "关闭前台手动") } }
                    ))

                    SliderRow(icon: "magnifyingglass", label: "BLE 扫描时长",
                              value: $settingsStore.settings.bleScanDuration, range: 20...300, step: 5,
                              format: "\(Int(settingsStore.settings.bleScanDuration))s", tint: AppTheme.orange) { value in
                        VehicleEventLogStore.shared.add(.keyless, "修改BLE扫描时长", detail: "\(Int(value))s")
                    }

                    SliderRow(icon: "timer", label: "BLE 扫描间隔",
                              value: $settingsStore.settings.bleScanInterval, range: 0...300, step: 5,
                              format: settingsStore.settings.bleScanInterval <= 0 ? "无间隙" : "\(Int(settingsStore.settings.bleScanInterval))s", tint: AppTheme.accent) { value in
                        let text = value <= 0 ? "无间隙" : "\(Int(value))s"
                        VehicleEventLogStore.shared.add(.keyless, "修改BLE扫描间隔", detail: text)
                    }

                    SliderRow(icon: "gauge", label: "重复指令间隔",
                              value: $settingsStore.settings.cmdInterval, range: 1...15, step: 1,
                              format: "\(Int(settingsStore.settings.cmdInterval))s", tint: AppTheme.purple) { value in
                        VehicleEventLogStore.shared.add(.keyless, "修改重复指令间隔", detail: "\(Int(value))s")
                    }
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
            ToggleRow(icon: "power", label: "解锁开关", isOn: Binding(
                get: { settingsStore.settings.unlockEnabled },
                set: { enabled in
                    settingsStore.settings.unlockEnabled = enabled
                    // 不互斥关 UI：启动电源打开时，解锁仅逻辑失效，设置项仍可调
                    VehicleEventLogStore.shared.add(.keyless, enabled ? "开启无感解锁" : "关闭无感解锁")
                }
            ))

            ToggleRow(icon: "power.circle", label: "启动电源", isOn: Binding(
                get: { settingsStore.settings.powerStartEnabled },
                set: { enabled in
                    settingsStore.settings.powerStartEnabled = enabled
                    // 打开后无感靠近优先 BLE 启动电源；不关闭解锁开关，避免阈值等设置被折叠
                    VehicleEventLogStore.shared.add(
                        .keyless,
                        enabled ? "开启无感启动电源" : "关闭无感启动电源",
                        detail: enabled ? "靠近车辆后自动解锁启动电源" : ""
                    )
                }
            ))

            // 解锁或启动电源任一开启时，都显示阈值/靠近确认等设置
            if settingsStore.settings.unlockEnabled || settingsStore.settings.powerStartEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $settingsStore.settings.unlockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(settingsStore.settings.unlockThreshold)) dBm", tint: AppTheme.green) { value in
                        VehicleEventLogStore.shared.add(.keyless, "修改解锁阈值", detail: "\(Int(value)) dBm")
                    }

                    SliderRow(icon: "timer", label: "靠近确认",
                              value: $settingsStore.settings.unlockApproachDuration, range: 0...5, step: 0.5,
                              format: String(format: "%.1fs", settingsStore.settings.unlockApproachDuration), tint: AppTheme.green) { value in
                        VehicleEventLogStore.shared.add(.keyless, "修改解锁确认时长", detail: String(format: "%.1fs", value))
                    }

                    ToggleRow(icon: "iphone.radiowaves.left.and.right", label: "震动反馈", isOn: Binding(
                        get: { settingsStore.settings.unlockVibrate },
                        set: { enabled in
                            settingsStore.settings.unlockVibrate = enabled
                            VehicleEventLogStore.shared.add(.keyless, enabled ? "开启解锁震动反馈" : "关闭解锁震动反馈")
                        }
                    ))

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
            ToggleRow(icon: "power", label: "上锁开关", isOn: Binding(
                get: { settingsStore.settings.lockEnabled },
                set: { enabled in
                    settingsStore.settings.lockEnabled = enabled
                    VehicleEventLogStore.shared.add(.keyless, enabled ? "开启无感上锁" : "关闭无感上锁")
                }
            ))

            if settingsStore.settings.lockEnabled {
                VStack(spacing: 12) {
                    SliderRow(icon: "wifi", label: "dBm 阈值",
                              value: $settingsStore.settings.lockThreshold, range: -110...(-30), step: 1,
                              format: "\(Int(settingsStore.settings.lockThreshold)) dBm", tint: AppTheme.red) { value in
                        VehicleEventLogStore.shared.add(.keyless, "修改上锁阈值", detail: "\(Int(value)) dBm")
                    }

                    SliderRow(icon: "gauge", label: "上锁延迟",
                              value: $settingsStore.settings.lockDelay, range: 0...60, step: 1,
                              format: "\(Int(settingsStore.settings.lockDelay))s", tint: AppTheme.red) { value in
                        VehicleEventLogStore.shared.add(.keyless, "修改上锁延迟", detail: "\(Int(value))s")
                    }

                    ToggleRow(icon: "iphone.radiowaves.left.and.right", label: "震动反馈", isOn: Binding(
                        get: { settingsStore.settings.lockVibrate },
                        set: { enabled in
                            settingsStore.settings.lockVibrate = enabled
                            VehicleEventLogStore.shared.add(.keyless, enabled ? "开启上锁震动反馈" : "关闭上锁震动反馈")
                        }
                    ))

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

                    // 上锁弹窗在前；未关不自动上锁依赖它，必须先开弹窗。
                    ToggleRow(icon: "bell.fill", label: "上锁弹窗", isOn: Binding(
                        get: { settingsStore.settings.lockPopup },
                        set: { enabled in
                            settingsStore.settings.lockPopup = enabled
                            if !enabled {
                                settingsStore.settings.lockRequireClosedBody = false
                            }
                            VehicleEventLogStore.shared.add(
                                .keyless,
                                enabled ? "开启上锁弹窗" : "关闭上锁弹窗",
                                detail: enabled ? "允许无感上锁结果与未关提醒推送" : "同时关闭「未关不自动上锁」"
                            )
                        }
                    ))

                    if settingsStore.settings.lockPopup {
                        ToggleRow(icon: "exclamationmark.shield.fill", label: "未关不自动上锁", isOn: Binding(
                            get: { settingsStore.settings.lockRequireClosedBody },
                            set: { enabled in
                                settingsStore.settings.lockRequireClosedBody = enabled
                                VehicleEventLogStore.shared.add(
                                    .keyless,
                                    enabled ? "开启未关不自动上锁" : "关闭未关不自动上锁",
                                    detail: enabled
                                        ? "门或尾门未关时先拦截上锁，再 HTTP 点名推送；车窗只提醒不拦锁"
                                        : "离开后直接尝试上锁，锁后 HTTP 检查并推送未关部位"
                                )
                            }
                        ))
                        Text(settingsStore.settings.lockRequireClosedBody
                             ? "开启后：门或尾门未关时不执行无感上锁，并推送具体未关部位。车窗不阻断上锁，只提醒。"
                             : "关闭后：离开后仍会尝试无感上锁；锁后通过 HTTP 检查，并推送未关的门、车窗或尾门。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("开启「上锁弹窗」后，可设置是否在门/尾门未关时拦截无感上锁，并接收未关部位推送。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

            SliderRow(icon: "gauge", label: "震动强度",
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
