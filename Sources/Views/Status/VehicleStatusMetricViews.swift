import SwiftUI

struct VehicleStatusMetric: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let status: String?
    let color: Color

    init(icon: String, label: String, value: String, status: String? = nil, color: Color) {
        self.icon = icon
        self.label = label
        self.value = value
        self.status = status
        self.color = color
    }

    init(item: PopupStatusItem) {
        self.icon = item.icon
        self.label = item.label
        self.value = item.value
        self.status = nil
        self.color = item.color
    }
}

struct VehicleStatusMetricGrid: View {
    let metrics: [VehicleStatusMetric]

    init(metrics: [VehicleStatusMetric]) { self.metrics = metrics }
    init(items: [PopupStatusItem]) { self.metrics = items.map { VehicleStatusMetric(item: $0) } }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(metrics) { metric in
                VehicleStatusMetricCard(metric: metric)
            }
        }
    }
}

struct VehicleStatusMetricList: View {
    let metrics: [VehicleStatusMetric]

    init(metrics: [VehicleStatusMetric]) { self.metrics = metrics }
    init(items: [PopupStatusItem]) { self.metrics = items.map { VehicleStatusMetric(item: $0) } }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(metrics) { metric in
                VehicleStatusMetricCard(metric: metric)
            }
        }
    }
}

struct VehicleStatusMetricCard: View {
    let metric: VehicleStatusMetric

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(metric.color.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: metric.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(metric.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.value)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let status = metric.status {
                        Text(status)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(metric.color)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
