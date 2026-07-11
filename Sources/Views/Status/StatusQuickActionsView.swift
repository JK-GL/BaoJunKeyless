import SwiftUI

struct QuickActionsView: View, Equatable {
    let onCommand: (CommandAction) -> Void
    let vehicleState: VehicleState
    /// 当前是否可走 BLE 控制（鉴权成功且可发 BLE 命令）
    var bleControlAvailable: Bool = false

    static func == (lhs: QuickActionsView, rhs: QuickActionsView) -> Bool {
        lhs.vehicleState.locked == rhs.vehicleState.locked
            && lhs.vehicleState.power == rhs.vehicleState.power
            && lhs.vehicleState.acOn == rhs.vehicleState.acOn
            && lhs.vehicleState.windowsClosed == rhs.vehicleState.windowsClosed
            && lhs.bleControlAvailable == rhs.bleControlAvailable
    }

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
                        state: vehicleState,
                        showBLEBadge: bleControlAvailable && action.asVehicleCommand(state: vehicleState, temperature: nil).kind.supportsBLEControl
                    ) {
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
    let showBLEBadge: Bool
    let onTap: () -> Void

    private var color: Color { action.resolvedColor(state: state) }
    private var icon: String { action.icon(state: state) }
    private var label: String { action.label(state: state) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.10))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color)
                    }

                    if showBLEBadge {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.green)
                            .frame(width: 15, height: 15)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .frame(width: 15, height: 15)
                            )
                            .offset(x: 6, y: -5)
                            .accessibilityLabel("支持蓝牙控制")
                    }
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
