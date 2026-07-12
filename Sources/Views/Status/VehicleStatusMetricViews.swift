import SwiftUI

struct VehicleStatusMetric: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    let value: String
    let status: String?
    let color: Color

    init(icon: String, label: String, value: String, status: String? = nil, color: Color) {
        self.id = "\(icon)|\(label)"
        self.icon = icon
        self.label = label
        self.value = value
        self.status = status
        self.color = color
    }

    init(item: PopupStatusItem) {
        self.id = item.id
        self.icon = item.icon
        self.label = item.label
        self.value = item.value
        self.status = nil
        self.color = item.color
    }

    static func == (lhs: VehicleStatusMetric, rhs: VehicleStatusMetric) -> Bool {
        lhs.id == rhs.id && lhs.value == rhs.value && lhs.status == rhs.status
    }
}

struct VehicleStatusMetricGrid: View {
    let metrics: [VehicleStatusMetric]

    init(metrics: [VehicleStatusMetric]) { self.metrics = metrics }
    init(items: [PopupStatusItem]) { self.metrics = items.map { VehicleStatusMetric(item: $0) } }

    var body: some View {
        // ScrollView 内避免 LazyVGrid 异步量高导致相邻卡片重叠
        let rows = stride(from: 0, to: metrics.count, by: 2).map { idx -> [VehicleStatusMetric] in
            Array(metrics[idx..<min(idx + 2, metrics.count)])
        }
        return VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row) { metric in
                        VehicleStatusMetricCard(metric: metric)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
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

struct VehicleStatusMetricCard: View, Equatable {
    let metric: VehicleStatusMetric

    static func == (lhs: VehicleStatusMetricCard, rhs: VehicleStatusMetricCard) -> Bool {
        lhs.metric == rhs.metric
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(metric.color.opacity(0.09))
                    .frame(width: 34, height: 34)
                Image(systemName: metric.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(metric.color.opacity(0.95))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.56))
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
