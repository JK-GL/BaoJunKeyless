import SwiftUI

struct SettingsDiagnosticsSection: View {
    @EnvironmentObject var vehicleStore: VehicleStateStore
    @AppStorage(AppDiagnosticsSettings.quickActionsDebugModeKey) private var quickActionsDebugMode = true

    var body: some View {
        SettingsPanelView(
            title: "诊断与联调",
            subtitle: "收纳开发期调试入口，状态页保持正式车控界面。"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ToggleRow(
                    icon: "wrench.fill",
                    label: "快捷操作联动状态",
                    isOn: $quickActionsDebugMode
                )

                Text("开启后，快捷操作会同步切换模拟车辆状态，用于 UI 联调；关闭后仅展示指令弹窗，不改动状态页。")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(Color.white.opacity(0.1))

                HStack {
                    Label("油量栏显示", systemImage: "fuelpump")
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Spacer()

                    Picker("", selection: $vehicleStore.fuelBarMode) {
                        ForEach(FuelBarMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

            }
        }
    }
}
