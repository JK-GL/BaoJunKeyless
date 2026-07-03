import SwiftUI

struct QuickActionsView: View {
    let onCommand: (CommandAction) -> Void
    let vehicleState: VehicleState

    private let gridColumns = [
        GridItem(.flexible(), spacing: AppSpacing.compact),
        GridItem(.flexible(), spacing: AppSpacing.compact),
        GridItem(.flexible(), spacing: AppSpacing.compact)
    ]

    private let orderedActions: [CommandAction] = [
        .lockUnlock, .remoteStart, .findCar,
        .acToggle,   .quickCool,   .windowToggle
    ]

    var body: some View {
        CardView(title: "快捷操作", icon: "bolt.fill", iconColor: AppTheme.orange) {
            LazyVGrid(columns: gridColumns, spacing: AppSpacing.compact) {
                ForEach(orderedActions) { action in
                    CommandGridButton(
                        action: action,
                        state: vehicleState
                    ) {
                        onCommand(action)
                        DispatchQueue.main.async {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        }
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

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }

                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.segmented, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.segmented, style: .continuous)
                            .stroke(color.opacity(0.14), lineWidth: 0.8)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.segmented, style: .continuous))
        }
        .buttonStyle(ResponsiveButtonStyle())
    }
}
