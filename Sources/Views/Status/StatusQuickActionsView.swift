import SwiftUI

struct QuickActionsView: View {
    let onCommand: (CommandAction) -> Void
    let vehicleState: VehicleState

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let orderedActions: [CommandAction] = [
        .lockUnlock, .remoteStart, .findCar,
        .acToggle,   .quickCool,   .windowToggle
    ]

    var body: some View {
        CardView(title: "快捷操作", icon: "bolt.fill", iconColor: AppTheme.orange) {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(orderedActions) { action in
                    CommandGridButton(
                        action: action,
                        state: vehicleState
                    ) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onCommand(action)
                    }
                }
            }
        }
    }
}

// MARK: - 网格按钮
private struct CommandGridButton: View {
    let action: CommandAction
    let state: VehicleState
    let onTap: () -> Void

    private var color: Color { action.resolvedColor(state: state) }
    private var icon: String { action.icon(state: state) }
    private var label: String { action.label(state: state) }

    private var isActive: Bool {
        switch action {
        case .lockUnlock:
            return state.locked == true
        case .remoteStart:
            return state.power == .on || state.power == .ready
        case .acToggle:
            return state.acOn == true
        case .windowToggle:
            return state.windowsClosed == false
        case .quickCool, .findCar:
            return false
        }
    }

    private var isSensitiveAction: Bool {
        switch action {
        case .lockUnlock:
            return state.locked == true
        case .remoteStart:
            return state.power == .off || state.power == .acc
        case .windowToggle:
            return state.windowsClosed == true
        case .quickCool:
            return true
        case .acToggle, .findCar:
            return false
        }
    }

    private var statusBadgeText: String {
        switch action {
        case .lockUnlock:
            return state.locked == true ? "已锁" : "未锁"
        case .remoteStart:
            return state.power == .off ? "熄火" : state.power.title
        case .findCar:
            return "定位"
        case .acToggle:
            return state.acOn == true ? "运行" : "关闭"
        case .windowToggle:
            return state.windowsClosed == false ? "已开" : "已关"
        case .quickCool:
            return "确认"
        }
    }

    private var backgroundOpacity: Double {
        if isSensitiveAction { return 0.13 }
        return isActive ? 0.16 : AppOpacity.controlFill
    }

    private var strokeOpacity: Double {
        if isSensitiveAction { return 0.38 }
        return isActive ? 0.32 : 0.14
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(isActive || isSensitiveAction ? 0.18 : 0.10))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(color)
                    }

                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)

                Text(statusBadgeText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSensitiveAction ? AppTheme.orange : color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((isSensitiveAction ? AppTheme.orange : color).opacity(0.14))
                    )
                    .padding(7)
            }
            .background(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(color.opacity(backgroundOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke((isSensitiveAction ? AppTheme.orange : color).opacity(strokeOpacity), lineWidth: isActive || isSensitiveAction ? 1.1 : 0.8)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
