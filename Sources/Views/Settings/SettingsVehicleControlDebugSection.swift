import SwiftUI

struct SettingsVehicleControlDebugSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var routeMode: VehicleControlRouteMode
    @Binding var toastText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .font(.system(size: 15, weight: .semibold))
                Text("车控路由")
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
    }
}
