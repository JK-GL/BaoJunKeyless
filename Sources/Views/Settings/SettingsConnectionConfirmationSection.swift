import SwiftUI

/// 连接通道、快捷确认、熄火提醒与状态页展示。
struct SettingsConnectionConfirmationSection: View {
    @EnvironmentObject var keylessSettings: KeylessSettingsStore
    @AppStorage("Settings.connectionConfirmationSectionExpanded") private var isExpanded = false

    private var summaryText: String {
        let mqtt = keylessSettings.settings.mqttEnabled ? "MQTT开" : "MQTT关"
        let confirm = keylessSettings.settings.lockUnlockConfirmationEnabled ? "确认开" : "确认关"
        let monitor = keylessSettings.settings.powerOffBodyMonitorEnabled ? "熄火监测开" : "熄火监测关"
        let visual: String
        if keylessSettings.settings.statusRadarEnabled {
            visual = "雷达"
        } else if keylessSettings.settings.statusLargeCarImageEnabled {
            visual = "大车图"
        } else if keylessSettings.settings.statusProximityStripEnabled {
            visual = "关系条"
        } else {
            visual = "极简"
        }
        return "\(mqtt) · \(confirm) · \(monitor) · \(visual)"
    }

    var body: some View {
        CollapsibleCard(
            title: "连接与提醒",
            icon: "bell.badge.fill",
            iconColor: AppTheme.accent,
            isExpanded: $isExpanded,
            headerExtra: {
                Text(summaryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                settingToggle(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "MQTT 实时辅助",
                    subtitle: "开启后使用 MQTT 接收增量提示并触发 HTTP 刷新；关闭后不连接 MQTT，并隐藏状态胶囊。",
                    isOn: binding(\.mqttEnabled, title: "MQTT 实时辅助")
                )

                Divider().background(Color.white.opacity(0.08))

                settingToggle(
                    icon: "checkmark.shield.fill",
                    title: "锁车/解锁二次确认",
                    subtitle: "开启后点击锁车或解锁需要再次确认；关闭后直接执行。其他车控确认不受影响。",
                    isOn: binding(\.lockUnlockConfirmationEnabled, title: "锁车/解锁二次确认")
                )

                Divider().background(Color.white.opacity(0.08))

                settingToggle(
                    icon: "exclamationmark.triangle.fill",
                    title: "熄火监测门窗",
                    subtitle: "开启后：车辆熄火且门/窗/尾门未关时立刻推送，之后每 10 分钟一次，直到全部关闭。关闭后不监测。",
                    isOn: binding(\.powerOffBodyMonitorEnabled, title: "熄火监测门窗")
                )

                Divider().background(Color.white.opacity(0.08))

                settingToggle(
                    icon: "dot.radiowaves.left.and.right",
                    title: "显示雷达",
                    subtitle: "开启后状态页显示雷达圆盘与车标。与大车图、关系条互斥；关闭后可只留距离和地址。",
                    isOn: visualBinding(.radar, title: "显示雷达")
                )

                Divider().background(Color.white.opacity(0.08))

                settingToggle(
                    icon: "car.fill",
                    title: "显示大车图",
                    subtitle: "开启后显示车辆大图。与雷达、关系条互斥；都关时仅保留距离和地址。",
                    isOn: visualBinding(.largeCar, title: "显示大车图")
                )

                Divider().background(Color.white.opacity(0.08))

                settingToggle(
                    icon: "figure.stand",
                    title: "显示关系条",
                    subtitle: "开启后显示「人 — 信号 — 车」横排：间距随离车距离变化，中间为 GPS/RSSI。与雷达、大车图互斥。",
                    isOn: visualBinding(.proximityStrip, title: "显示关系条")
                )
            }
        }
    }

    private enum VisualMode {
        case radar, largeCar, proximityStrip
    }

    private func binding(_ keyPath: WritableKeyPath<KeylessSettings, Bool>, title: String) -> Binding<Bool> {
        Binding(
            get: { keylessSettings.settings[keyPath: keyPath] },
            set: { value in
                keylessSettings.settings[keyPath: keyPath] = value
                VehicleEventLogStore.shared.add(.system, value ? "开启\(title)" : "关闭\(title)")
            }
        )
    }

    /// 三选一视觉模式：开一个自动关另外两个；关一个不自动打开别的。
    private func visualBinding(_ mode: VisualMode, title: String) -> Binding<Bool> {
        Binding(
            get: {
                switch mode {
                case .radar: return keylessSettings.settings.statusRadarEnabled
                case .largeCar: return keylessSettings.settings.statusLargeCarImageEnabled
                case .proximityStrip: return keylessSettings.settings.statusProximityStripEnabled
                }
            },
            set: { value in
                if value {
                    keylessSettings.settings.statusRadarEnabled = (mode == .radar)
                    keylessSettings.settings.statusLargeCarImageEnabled = (mode == .largeCar)
                    keylessSettings.settings.statusProximityStripEnabled = (mode == .proximityStrip)
                } else {
                    switch mode {
                    case .radar: keylessSettings.settings.statusRadarEnabled = false
                    case .largeCar: keylessSettings.settings.statusLargeCarImageEnabled = false
                    case .proximityStrip: keylessSettings.settings.statusProximityStripEnabled = false
                    }
                }
                VehicleEventLogStore.shared.add(.system, value ? "开启\(title)" : "关闭\(title)")
            }
        )
    }

    @ViewBuilder
    private func settingToggle(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ToggleRow(icon: icon, label: title, isOn: isOn)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.50))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 30)
        }
    }
}
