import SwiftUI

/// 可选连接通道与快捷锁解确认。两项均默认开启。
struct SettingsConnectionConfirmationSection: View {
    @EnvironmentObject var keylessSettings: KeylessSettingsStore

    var body: some View {
        SettingsPanelView(title: "连接与确认") {
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
