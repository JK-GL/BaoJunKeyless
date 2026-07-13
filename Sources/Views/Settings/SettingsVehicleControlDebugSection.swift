import SwiftUI

/// 车控路由：折叠组，与后台增强同一套 CollapsibleCard 样式
struct SettingsVehicleControlDebugSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var routeMode: VehicleControlRouteMode
    @Binding var toastText: String?

    @AppStorage("Settings.vehicleControlRouteSectionExpanded") private var isExpanded = false

    var body: some View {
        CollapsibleCard(
            title: "车控路由",
            icon: "arrow.triangle.branch",
            iconColor: Color.orange.opacity(0.95),
            isExpanded: $isExpanded,
            headerExtra: {
                Text(routeMode.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅影响解锁 / 上锁 / 启动 / 熄火；寻车、空调等仍走原通道。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

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
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(routeMode == mode ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(routeMode == mode ? theme.accent.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
