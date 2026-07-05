import SwiftUI

struct SettingsVehicleControlDebugSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var routeMode: VehicleControlRouteMode
    @Binding var toastText: String?
    @State private var binding = VehicleBLEBindingStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .font(.system(size: 15, weight: .semibold))
                Text("车控调试")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("仅影响解锁/上锁/启动/熄火")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(VehicleControlRouteMode.allCases, id: \.rawValue) { mode in
                    Button {
                        routeMode = mode
                        NotificationCenter.default.post(name: .vehicleControlRouteModeChanged, object: nil)
                        withAnimation { toastText = "车控路由：\(mode.title)" }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: routeMode == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(routeMode == mode ? theme.accent : Color.white.opacity(0.35))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(mode.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(routeMode == mode ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(routeMode == mode ? theme.accent.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: binding == nil ? "link.badge.plus" : "link.circle.fill")
                        .foregroundStyle(binding == nil ? Color.white.opacity(0.45) : AppTheme.green)
                    Text("蓝牙绑定")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if binding != nil {
                        Button("清除绑定") {
                            VehicleBLEBindingStore.clear()
                            binding = nil
                            NotificationCenter.default.post(name: .vehicleControlRouteModeChanged, object: nil)
                            withAnimation { toastText = "已清除蓝牙绑定" }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                    }
                }

                Text(binding?.displaySummary ?? "尚未绑定。首次 BLE 鉴权成功后会自动绑定，下次优先直连。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            Text("建议排错顺序：先“强制BLE”复现连接/回包问题，再切“强制HTTP”对比云控链路，最后回到“自动”。")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .onAppear { binding = VehicleBLEBindingStore.load() }
    }
}
