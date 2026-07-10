import SwiftUI

struct SettingsFuelDisplaySection: View {
    @ObservedObject private var fuelBarModeStore = FuelBarModeStore.shared

    var body: some View {
        SettingsPanelView(title: "油量显示") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    fuelModeButton(.auto, title: "自动")
                    fuelModeButton(.show, title: "强制显示")
                    fuelModeButton(.hide, title: "强制隐藏")
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.segmented, style: .continuous)
                        .fill(AppSurface.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.segmented, style: .continuous)
                        .stroke(AppSurface.sectionStroke, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func fuelModeButton(_ mode: FuelBarMode, title: String) -> some View {
        let selected = fuelBarModeStore.mode == mode
        Button {
            if let store = VehicleStateStoreBridge.current {
                store.setFuelBarMode(mode)
            } else {
                fuelBarModeStore.setMode(mode)
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? AppTheme.orange : Color.white.opacity(0.02))
                )
        }
        .buttonStyle(.plain)
    }
}

/// Lightweight bridge so settings can trigger energy-type recompute without observing the whole vehicle store.
enum VehicleStateStoreBridge {
    static weak var current: VehicleStateStore?
}
