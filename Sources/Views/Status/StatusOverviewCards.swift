import SwiftUI

struct QuickStatusTripletView: View {
    let totalMileageText: String
    let averageFuelConsumptionText: String
    let yesterdayMileageText: String

    var body: some View {
        CardView {
            HStack(spacing: 10) {
                quickMetric(icon: "car.fill", title: "总里程", value: totalMileageText, color: AppTheme.accent)
                quickMetric(icon: "fuelpump.fill", title: "平均油耗", value: averageFuelConsumptionText, color: AppTheme.orange)
                quickMetric(icon: "calendar", title: "昨日里程", value: yesterdayMileageText, color: Color.white.opacity(0.72))
            }
        }
    }

    @ViewBuilder
    private func quickMetric(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }
}

struct VehicleHeaderSummaryView: View {
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

struct BatteryGaugesView: View {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "电池系统", icon: "battery.100", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct TemperatureView: View {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "温度监控", icon: "thermometer", iconColor: AppTheme.orange) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct ChargingStatusView: View {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "充电状态", icon: "bolt.circle.fill", iconColor: AppTheme.orange) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct BodyStatusView: View {
    let dashboard: VehicleDashboardState

    var body: some View {
        CardView(
            title: "车身状态",
            icon: "car.fill",
            iconColor: AppTheme.green,
            headerAccessory: {
                Text(dashboard.bodyStatusNormalText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dashboard.warningMessages.isEmpty ? AppTheme.green : AppTheme.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill((dashboard.warningMessages.isEmpty ? AppTheme.green : AppTheme.orange).opacity(0.12)))
            }
        ) {
            VStack(spacing: 10) {
                VehicleStatusMetricGrid(items: dashboard.metrics.bodyStatus)

                let warnings = dashboard.warningMessages
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

struct DrivingStatusView: View {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "驾驶状态", icon: "scope", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct LightingStatusView: View {
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
        HStack(alignment: .top, spacing: -18) {
            left.frame(maxWidth: .infinity)
            right.frame(maxWidth: .infinity)
        }
    }
}
