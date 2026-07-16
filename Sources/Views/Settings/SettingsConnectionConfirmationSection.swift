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
                    subtitle: "开启后状态页显示雷达圆盘与车标。与「显示大车图」互斥；关闭后可只留距离和地址。",
                    isOn: exclusiveBinding(enableRadar: true, title: "显示雷达")
                )

                Divider().background(Color.white.opacity(0.08))

                settingToggle(
                    icon: "car.fill",
                    title: "显示大车图",
                    subtitle: "开启后在原雷达位置显示车辆大图。与「显示雷达」互斥；两者都关时仅保留距离和地址。",
                    isOn: exclusiveBinding(enableRadar: false, title: "显示大车图")
                )
            }
        }
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

    /// 雷达 / 大车图互斥绑定：开一侧自动关另一侧；关一侧不自动打开另一侧。
    private func exclusiveBinding(enableRadar: Bool, title: String) -> Binding<Bool> {
        Binding(
            get: {
                if enableRadar {
                    return keylessSettings.settings.statusRadarEnabled
                }
                return keylessSettings.settings.statusLargeCarImageEnabled
            },
            set: { value in
                if enableRadar {
                    if value {
                        keylessSettings.settings.statusLargeCarImageEnabled = false
                        keylessSettings.settings.statusRadarEnabled = true
                    } else {
                        keylessSettings.settings.statusRadarEnabled = false
                    }
                } else {
                    if value {
                        keylessSettings.settings.statusRadarEnabled = false
                        keylessSettings.settings.statusLargeCarImageEnabled = true
                    } else {
                        keylessSettings.settings.statusLargeCarImageEnabled = false
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
