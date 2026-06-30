import SwiftUI

struct SettingsFuelDisplaySection: View {
    @EnvironmentObject var vehicleStore: VehicleStateStore

    var body: some View {
        SettingsPanelView(title: "油量显示") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    fuelModeButton(.auto, title: "自动")
                    fuelModeButton(.show, title: "强制显示")
                    fuelModeButton(.hide, title: "强制隐藏")
                }
            }
        }
    }

    @ViewBuilder
    private func fuelModeButton(_ mode: FuelBarMode, title: String) -> some View {
        let selected = vehicleStore.fuelBarMode == mode
        Button {
            vehicleStore.setFuelBarMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? AppTheme.orange : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
