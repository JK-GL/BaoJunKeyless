import SwiftUI

struct StatusTopBarSection: View {
    let isRefreshing: Bool
    let refreshScale: CGFloat
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            PageHeaderView(title: "宝骏云海")
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: isRefreshing ? "hourglass" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .frame(width: 24, height: 24)
                    .scaleEffect(refreshScale)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

struct StatusPillsSection: View {
    let modeIcon: String
    let modeText: String
    let modeColor: Color

    var body: some View {
        HStack(spacing: 6) {
            StatusPill(icon: "dot.radiowaves.left.and.right", text: "BLE 未连接", color: Color.white.opacity(0.45))
            StatusPill(icon: "key.fill", text: "密钥正常", color: AppTheme.green)
            StatusPill(icon: modeIcon, text: modeText, color: modeColor)
            StatusPill(icon: "lock.fill", text: "已锁车", color: AppTheme.green)
        }
        .padding(.horizontal, 20)
    }
}
