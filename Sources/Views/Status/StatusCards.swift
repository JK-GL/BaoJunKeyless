import SwiftUI

struct QuickActionsView: View {
    @StateObject private var vehicleState = VehicleStateHolder()

    let onCommand: (CommandAction) -> Void

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let orderedActions: [CommandAction] = [
        .lockUnlock, .remoteStart, .findCar,
        .acToggle,   .tempAdjust,  .quickCool
    ]

    var body: some View {
        CardView(title: "快捷操作", icon: "bolt.fill", iconColor: AppTheme.orange) {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(orderedActions) { action in
                    CommandGridButton(
                        action: action,
                        state: vehicleState.state
                    ) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onCommand(action)
                    }
                }
            }
        }
    }

    var vehicleStateValue: VehicleState { vehicleState.state }
}

// MARK: - 车辆状态占位（MQTT 接入前使用）
private class VehicleStateHolder: ObservableObject {
    @Published var state: VehicleState = .placeholder
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct VehicleHeaderSummaryView: View {
    var totalRangeKm: Int = 795
    var electricRangeKm: Int = 115
    var electricPercent: Double = 0.52
    var fuelRangeKm: Int = 680
    var fuelPercent: Double = 0.78
    var isCharging: Bool = false
    var chargingPowerText: String = "3.2 kW"
    var updatedAt: String = "17:59:34"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 12) {
                totalRangeBlock
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .bottom, spacing: 10) {
                    summaryColumn(
                        title: "电量",
                        rangeText: "\(electricRangeKm)km",
                        percentText: "\(Int(electricPercent * 100))%",
                        percent: electricPercent,
                        color: AppTheme.accent
                    )

                    summaryColumn(
                        title: "油量",
                        rangeText: "\(fuelRangeKm)km",
                        percentText: "\(Int(fuelPercent * 100))%",
                        percent: fuelPercent,
                        color: AppTheme.orange
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

            Text("更新时间：\(updatedAt)")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .padding(.horizontal, 20)
    }

    private var totalRangeBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(totalRangeKm)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("km")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Text("综合续航")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.bottom, 1)
    }

    private func summaryColumn(title: String, rangeText: String, percentText: String, percent: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))

                Text(rangeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(percentText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
                    .scaleEffect(x: max(0, min(1, percent)), y: 1, anchor: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RangeCardView: View {
    var body: some View {
        EmptyView()
    }
}

struct RangeRow: View {
    let icon: String; let iconColor: Color; let iconBg: Color
    let label: String; let percent: String; let percentColor: Color
    let range: String; let barPercent: Double; let barColor: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(iconBg).frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(iconColor)
                }
                Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
                Text(percent).font(.system(size: 14, weight: .bold)).foregroundColor(percentColor)
                Spacer()
                Text(range).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [barColor.opacity(0.8), barColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * barPercent, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

struct BatteryGaugesView: View {
    private let metrics: [VehicleStatusMetric] = [
        VehicleStatusMetric(icon: "battery.100.bolt", label: "剩余", value: "17.8kWh", color: AppTheme.accent),
        VehicleStatusMetric(icon: "checkmark.seal.fill", label: "健康", value: "99%", color: AppTheme.green),
        VehicleStatusMetric(icon: "bolt.fill", label: "电压", value: "109.5V", color: AppTheme.accent),
        VehicleStatusMetric(icon: "car.fill", label: "小电瓶", value: "12.4V", color: AppTheme.accent)
    ]

    var body: some View {
        CardView(title: "电池系统", icon: "battery.100.bolt", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(metrics: metrics)
        }
    }
}

struct TemperatureView: View {
    private let metrics: [VehicleStatusMetric] = [
        VehicleStatusMetric(icon: "thermometer", label: "车内", value: "22°C", color: AppTheme.accent),
        VehicleStatusMetric(icon: "snowflake", label: "空调", value: "17°C", color: AppTheme.orange),
        VehicleStatusMetric(icon: "thermometer.medium", label: "电池", value: "25°C", color: AppTheme.green),
        VehicleStatusMetric(icon: "gearshape.fill", label: "电机", value: "27°C", color: AppTheme.green),
        VehicleStatusMetric(icon: "cpu.fill", label: "逆变", value: "27°C", color: AppTheme.green)
    ]

    var body: some View {
        CardView(title: "温度监控", icon: "thermometer.medium", iconColor: AppTheme.orange) {
            VehicleStatusMetricList(metrics: metrics)
        }
    }
}

struct ChargingStatusView: View {
    private let metrics: [VehicleStatusMetric] = [
        VehicleStatusMetric(icon: "bolt.fill", label: "充电中", value: "否", color: AppTheme.orange),
        VehicleStatusMetric(icon: "gauge.medium", label: "功率", value: "--", color: Color.white.opacity(0.45)),
        VehicleStatusMetric(icon: "bolt.fill", label: "OBC电流", value: "0A", color: AppTheme.orange),
        VehicleStatusMetric(icon: "thermometer", label: "OBC温度", value: "--", color: Color.white.opacity(0.45)),
        VehicleStatusMetric(icon: "bolt.circle.fill", label: "状态", value: "--", color: Color.white.opacity(0.45))
    ]

    var body: some View {
        CardView(title: "充电状态", icon: "bolt.circle.fill", iconColor: AppTheme.orange) {
            VehicleStatusMetricList(metrics: metrics)
        }
    }
}

struct BodyStatusView: View {
    private let coreMetrics: [VehicleStatusMetric] = [
        VehicleStatusMetric(icon: "lock.fill", label: "车锁", value: "已锁车", color: AppTheme.green),
        VehicleStatusMetric(icon: "car.fill", label: "车门", value: "全关", color: AppTheme.green),
        VehicleStatusMetric(icon: "rectangle.fill", label: "车窗", value: "全关", color: AppTheme.green),
        VehicleStatusMetric(icon: "lock.fill", label: "尾门", value: "已锁", color: AppTheme.green)
    ]

    private var warningMessages: [String] {
        var warnings: [String] = []
        for metric in coreMetrics {
            if metric.color == AppTheme.orange || metric.color == AppTheme.red {
                if metric.value != "全关" && metric.value != "已锁车" && metric.value != "已锁" && metric.value != "关闭" && metric.value != "--" {
                    warnings.append("\(metric.label)\(metric.value)")
                }
            }
        }
        return warnings
    }

    var body: some View {
        CardView(title: "车身状态", icon: "car.fill", iconColor: AppTheme.green) {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Text("正常")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.green.opacity(0.12)))
                }
                VehicleStatusMetricGrid(metrics: coreMetrics)

                let warnings = warningMessages
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
    private let metrics: [VehicleStatusMetric] = [
        VehicleStatusMetric(icon: "scope", label: "方向盘", value: "0.0°", color: AppTheme.accent),
        VehicleStatusMetric(icon: "arrow.up.circle.fill", label: "油门", value: "0%", color: AppTheme.green),
        VehicleStatusMetric(icon: "stop.circle.fill", label: "刹车", value: "0%", color: AppTheme.green),
        VehicleStatusMetric(icon: "speedometer", label: "车速", value: "--", status: "km/h", color: Color.white.opacity(0.45))
    ]

    var body: some View {
        CardView(title: "驾驶状态", icon: "scope", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(metrics: metrics)
        }
    }
}

struct LightingStatusView: View {
    private let metrics: [VehicleStatusMetric] = [
        VehicleStatusMetric(icon: "lightbulb.fill", label: "近光灯", value: "关闭", color: AppTheme.orange),
        VehicleStatusMetric(icon: "sun.max.fill", label: "远光灯", value: "关闭", color: AppTheme.orange),
        VehicleStatusMetric(icon: "arrow.left.arrow.right", label: "左转向", value: "关闭", color: AppTheme.accent),
        VehicleStatusMetric(icon: "arrow.left.arrow.right", label: "右转向", value: "关闭", color: AppTheme.accent),
        VehicleStatusMetric(icon: "sun.min.fill", label: "示宽灯", value: "关闭", color: AppTheme.orange),
        VehicleStatusMetric(icon: "cloud.fog", label: "前雾灯", value: "关闭", color: AppTheme.orange)
    ]

    var body: some View {
        CardView(title: "灯光状态", icon: "lightbulb.fill", iconColor: AppTheme.orange) {
            VehicleStatusMetricGrid(metrics: metrics)
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

private struct VehicleStatusMetric: Identifiable {
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
}

private struct VehicleStatusMetricGrid: View {
    let metrics: [VehicleStatusMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(metrics) { metric in
                VehicleStatusMetricCard(metric: metric)
            }
        }
    }
}

private struct VehicleStatusMetricList: View {
    let metrics: [VehicleStatusMetric]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(metrics) { metric in
                VehicleStatusMetricCard(metric: metric)
            }
        }
    }
}

private struct VehicleStatusMetricCard: View {
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

struct VehicleInfoMergedCard: View {
    @State private var isExpanded = false
    @State private var showCopiedToast = false

    private struct RowData {
        let icon: String
        let label: String
        let value: String
        let mono: Bool
        let color: Color
        init(_ icon: String, _ label: String, _ value: String, mono: Bool = false, color: Color = .primary) {
            self.icon = icon; self.label = label; self.value = value; self.mono = mono; self.color = color
        }
    }

    private let rows: [RowData] = [
        RowData("car.fill",       "车型",       "宝骏云海 140km PHEV"),
        RowData("info.circle",    "VIN",        "LK6ADAH92RB765125", mono: true),
        RowData("person.fill",    "用户ID",     "17277894456", mono: true),
        RowData("key.fill",       "钥匙类型",   "owner（车主钥匙）", color: AppTheme.green),
        RowData("bolt.fill",      "BLE MAC",    "CC:45:A5:DA:B5:C3", mono: true, color: AppTheme.accent),
        RowData("number",         "Key ID",     "1123037", mono: true, color: AppTheme.accent),
        RowData("lock.fill",      "MasterKey",  "CED6...FB78", mono: true),
        RowData("dice.fill",      "Random",     "627E...7FA2", mono: true),
        RowData("clock.fill",     "有效期至",   "2038-01-01（永久）", color: AppTheme.green),
    ]

    private var fullText: String {
        """
        车型: 宝骏云海 140km PHEV
        VIN: LK6ADAH92RB765125
        用户ID: 17277894456
        钥匙类型: owner（车主钥匙）
        BLE MAC: CC:45:A5:DA:B5:C3
        Key ID: 1123037
        MasterKey: CED6CA88AF34726F43486E6D0040FB78
        Random: 627E346190C934150CBF795897A47FA2
        有效期至: 2038-01-01（永久）
        """
    }

    var body: some View {
        ZStack(alignment: .top) {
            CollapsibleCard(
                title: "车辆信息",
                icon: "car.fill",
                iconColor: AppTheme.accent,
                isExpanded: $isExpanded,
                headerExtra: {
                    Text("\(rows.count) 项")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        HStack(spacing: 10) {
                            Image(systemName: row.icon)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text(row.label)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(row.value)
                                .font(.system(size: row.mono ? 11 : 13,
                                              weight: .medium,
                                              design: row.mono ? .monospaced : .default))
                                .foregroundColor(row.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 7)

                        if idx < rows.count - 1 {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                Text("长按复制全部信息")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                UIPasteboard.general.string = fullText
                withAnimation { showCopiedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showCopiedToast = false }
                }
            }

            if showCopiedToast {
                ToastView(text: "已复制到剪贴板")
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                    .offset(y: -40)
            }
        }
    }
}
