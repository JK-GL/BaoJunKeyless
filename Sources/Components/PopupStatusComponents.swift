import SwiftUI

// MARK: - 弹窗内统一状态项
struct PopupStatusItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let color: Color
}

// MARK: - 弹窗内状态摘要组件
struct PopupStatusSummaryView: View {
    let items: [PopupStatusItem]

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(item.color)
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text(item.value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity)

                    if item.id != items.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1, height: 36)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }
}

// MARK: - 弹窗内温度滑块组件
struct PopupTemperatureSlider: View {
    let title: String
    @Binding var temperature: Double
    let range: ClosedRange<Double>
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                Spacer()
                Text("\(Int(temperature))°C")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
            }
            Slider(value: $temperature, in: range, step: 1)
                .tint(tint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
