import SwiftUI

struct QuickStatusTripletView: View, Equatable {
    let totalMileageText: String
    let averageFuelConsumptionText: String
    let yesterdayMileageText: String

    var body: some View {
        CardView {
            HStack(spacing: AppSpacing.compact) {
                quickMetric(icon: "car.fill", title: "总里程", value: totalMileageText, color: AppTheme.accent)
                quickMetric(icon: "fuelpump.fill", title: "平均油耗", value: averageFuelConsumptionText, color: AppTheme.orange)
                quickMetric(icon: "calendar", title: "昨日里程", value: yesterdayMileageText, color: Color.white.opacity(0.72))
            }
        }
    }

    @ViewBuilder
    private func quickMetric(icon: String, title: String, value: String, color: Color) -> some View {
        let parts = splitMetricValue(value)
        VStack(alignment: .center, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.number)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if !parts.unit.isEmpty {
                    Text(parts.unit)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func splitMetricValue(_ value: String) -> (number: String, unit: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "--" else { return (trimmed.isEmpty ? "--" : trimmed, "") }
        let numberEnd = trimmed.firstIndex { character in
            !(character.isNumber || character == ".")
        } ?? trimmed.endIndex
        let number = String(trimmed[..<numberEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = String(trimmed[numberEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (number.isEmpty ? trimmed : number, number.isEmpty ? "" : unit)
    }
}

struct VehicleHeaderSummaryView: View, Equatable {
    var energyType: VehicleEnergyType = .plugInHybrid
    var electricRangeKm: Int = 140
    var electricFullRangeKm: Int = 140
    var fuelRangeKm: Int = 1000
    var fuelFullRangeKm: Int = 1000
    var batteryPercentValue: Int? = nil
    var fuelPercentValue: Int? = nil
    var isCharging: Bool = false
    var chargingPowerText: String = "3.2 kW"
    var updatedAt: String = "17:59:34"

    private let barHeight: CGFloat = 4
    private let rowSpacing: CGFloat = 1
    private let columnSpacing: CGFloat = 10

    private var totalRangeKm: Int {
        switch energyType {
        case .plugInHybrid:
            return electricRangeKm + fuelRangeKm
        case .pureElectric:
            return electricRangeKm
        }
    }

    private var electricPercent: Double {
        if let percent = batteryPercentValue {
            return min(max(Double(percent) / 100.0, 0), 1)
        }
        guard electricFullRangeKm > 0 else { return 0 }
        return min(max(Double(electricRangeKm) / Double(electricFullRangeKm), 0), 1)
    }

    private var fuelPercent: Double {
        if let percent = fuelPercentValue {
            return min(max(Double(percent) / 100.0, 0), 1)
        }
        guard fuelFullRangeKm > 0 else { return 0 }
        return min(max(Double(fuelRangeKm) / Double(fuelFullRangeKm), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
                totalRangeTextRow
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                energySummaryBlock
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                // 让右侧能量块的“底部”（进度条底部）参与 firstTextBaseline 对齐。
                // 这样 820km 的文字基线/视觉底部 ≈ 进度条底部。
                .alignmentGuide(.firstTextBaseline) { dimension in
                    dimension[VerticalAlignment.bottom]
                }
            }

            if isCharging {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(AppTheme.orange)
                        .font(.system(size: 10, weight: .semibold))
                    Text("充电中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                    Text(chargingPowerText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(AppTheme.orange.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var energySummaryBlock: some View {
        switch energyType {
        case .plugInHybrid:
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: columnSpacing) {
                    energyHeader(title: "电量", rangeKm: electricRangeKm, percent: electricPercent, color: AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    energyHeader(title: "油量", rangeKm: fuelRangeKm, percent: fuelPercent, color: AppTheme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .bottom, spacing: columnSpacing) {
                    energyBar(percent: electricPercent, color: AppTheme.accent)
                    energyBar(percent: fuelPercent, color: AppTheme.orange)
                }
            }

        case .pureElectric:
            VStack(alignment: .leading, spacing: rowSpacing) {
                energyHeader(title: "电量", rangeKm: electricRangeKm, percent: electricPercent, color: AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                energyBar(percent: electricPercent, color: AppTheme.accent)
            }
        }
    }

    private var totalRangeTextRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(totalRangeKm)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("km")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }

    private func energyHeader(title: String, rangeKm: Int, percent: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))

            Text("\(rangeKm)km")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 2)

            Text("\(Int(percent * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private func energyBar(percent: Double, color: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: barHeight)

            Capsule()
                .fill(color)
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
                .scaleEffect(x: max(0, min(1, percent)), y: 1, anchor: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }
}

struct BatteryGaugesView: View, Equatable {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "电池系统", icon: "battery.100", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct TemperatureView: View, Equatable {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "温度监控", icon: "thermometer", iconColor: AppTheme.orange) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct ChargingStatusView: View, Equatable {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "充电状态", icon: "bolt.circle.fill", iconColor: AppTheme.orange) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct BodyStatusView: View, Equatable {
    let normalText: String
    let warnings: [String]
    let topMetrics: [PopupStatusItem]
    let detailMetrics: [PopupStatusItem]

    static func == (lhs: BodyStatusView, rhs: BodyStatusView) -> Bool {
        lhs.normalText == rhs.normalText
        && lhs.warnings == rhs.warnings
        && lhs.topMetrics == rhs.topMetrics
        && lhs.detailMetrics == rhs.detailMetrics
    }

    private var statusColor: Color {
        if normalText == "未知" || normalText == "部分未知" || normalText == "缓存" { return StatusTint.muted }
        return warnings.isEmpty ? StatusTint.successGreen : StatusTint.warningAmber
    }

    var body: some View {
        CardView(
            title: "车身状态",
            icon: "car.fill",
            iconColor: statusColor,
            headerAccessory: {
                Text(normalText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(statusColor.opacity(0.12)))
            }
        ) {
            VStack(spacing: 10) {
                VehicleStatusMetricGrid(items: topMetrics)
                BodyStatusDetailGrid(items: detailMetrics)

                if !warnings.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.orange)
                        Text("未关提醒：" + warnings.joined(separator: "；"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.orange.opacity(0.08)))
                }
            }
        }
    }
}

struct BodyStatusDetailGrid: View {
    let items: [PopupStatusItem]

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { idx in
            Array(items[idx..<min(idx + 2, items.count)])
        }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { item in
                        detailCell(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailCell(_ item: PopupStatusItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.color.opacity(0.82))
                .frame(width: 16)
            Text(item.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(item.value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }
}

struct TirePressureView: View, Equatable {
    let tireTemperatureText: String
    let metrics: [PopupStatusItem]

    static func == (lhs: TirePressureView, rhs: TirePressureView) -> Bool {
        lhs.tireTemperatureText == rhs.tireTemperatureText && lhs.metrics == rhs.metrics
    }

    private var tireTemperatureColor: Color {
        let digits = tireTemperatureText.filter { $0.isNumber }
        guard let value = Int(digits), !digits.isEmpty else { return StatusTint.muted }
        if value <= 40 { return StatusTint.successGreen }
        if value <= 55 { return StatusTint.warningAmber }
        return StatusTint.dangerRed
    }

    var body: some View {
        CardView(
            title: "胎压状态",
            icon: "sun.max.fill",
            iconColor: StatusTint.infoBlue,
            headerAccessory: {
                if tireTemperatureText != "--" {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.sun")
                            .font(.system(size: 10, weight: .semibold))
                        Text(tireTemperatureText)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(tireTemperatureColor)
                }
            }
        ) {
            let rows = stride(from: 0, to: metrics.count, by: 2).map { idx in
                Array(metrics[idx..<min(idx + 2, metrics.count)])
            }
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { metric in
                            TirePressureMetricCard(item: metric)
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
}

private struct TirePressureMetricCard: View {
    let item: PopupStatusItem

    private var pressureColor: Color {
        let digits = item.value.filter { $0.isNumber }
        guard let value = Int(digits), !digits.isEmpty else { return StatusTint.muted }
        if value >= 220 && value <= 260 { return StatusTint.successGreen }
        if (value >= 200 && value < 220) || (value > 260 && value <= 280) { return StatusTint.warningAmber }
        return StatusTint.dangerRed
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .frame(width: 22, height: 22)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(item.value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(pressureColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }
}

struct DrivingStatusView: View, Equatable {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "驾驶状态", icon: "scope", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct LightingStatusView: View, Equatable {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "灯光状态", icon: "lightbulb.fill", iconColor: AppTheme.orange) {
            VehicleStatusMetricGrid(items: metrics)
        }
    }
}

struct StatusDashboardPair<Left: View, Right: View>: View {
    private let left: Left
    private let right: Right

    init(@ViewBuilder _ left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            left.frame(maxWidth: .infinity)
            right.frame(maxWidth: .infinity)
        }
    }
}
