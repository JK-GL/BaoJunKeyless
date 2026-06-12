import SwiftUI

struct QuickActionsView: View {
    let onCommand: (CommandAction) -> Void
    let vehicleState: VehicleState

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let orderedActions: [CommandAction] = [
        .lockUnlock, .remoteStart, .findCar,
        .acToggle,   .quickCool,   .windowToggle
    ]

    var body: some View {
        CardView(title: "快捷操作", icon: "bolt.fill", iconColor: AppTheme.orange) {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(orderedActions) { action in
                    CommandGridButton(
                        action: action,
                        state: vehicleState
                    ) {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
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
    let onTap: () -> Void

    private var color: Color { action.resolvedColor(state: state) }
    private var icon: String { action.icon(state: state) }
    private var label: String { action.label(state: state) }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.10))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(color)
                }

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(color.opacity(0.14), lineWidth: 0.8)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct VehicleHeaderSummaryView: View {
    var electricRangeKm: Int = 140
    var electricFullRangeKm: Int = 140
    var fuelRangeKm: Int = 1000
    var fuelFullRangeKm: Int = 1000
    var isCharging: Bool = false
    var chargingPowerText: String = "3.2 kW"
    var updatedAt: String = "17:59:34"

    private let totalBlockWidth: CGFloat = 86
    private let topRowHeight: CGFloat = 30
    private let barHeight: CGFloat = 4
    private let rowSpacing: CGFloat = 3
    private let columnSpacing: CGFloat = 12

    private var totalRangeKm: Int {
        electricRangeKm + fuelRangeKm
    }

    private var electricPercent: Double {
        guard electricFullRangeKm > 0 else { return 0 }
        return min(max(Double(electricRangeKm) / Double(electricFullRangeKm), 0), 1)
    }

    private var fuelPercent: Double {
        guard fuelFullRangeKm > 0 else { return 0 }
        return min(max(Double(fuelRangeKm) / Double(fuelFullRangeKm), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: columnSpacing) {
                totalRangeTextRow
                    .frame(
                        width: totalBlockWidth,
                        height: topRowHeight + rowSpacing + barHeight,
                        alignment: .bottomLeading
                    )

                VStack(alignment: .leading, spacing: rowSpacing) {
                    HStack(alignment: .bottom, spacing: columnSpacing) {
                        energyHeader(title: "电量", rangeKm: electricRangeKm, percent: electricPercent, color: AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: topRowHeight, alignment: .bottomLeading)

                        energyHeader(title: "油量", rangeKm: fuelRangeKm, percent: fuelPercent, color: AppTheme.orange)
                            .frame(maxWidth: .infinity, minHeight: topRowHeight, alignment: .bottomLeading)
                    }

                    HStack(alignment: .center, spacing: columnSpacing) {
                        energyBar(percent: electricPercent, color: AppTheme.accent)
                        energyBar(percent: fuelPercent, color: AppTheme.orange)
                    }
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
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "电池系统", icon: "battery.100.bolt", iconColor: AppTheme.accent) {
            VehicleStatusMetricList(items: metrics)
        }
    }
}

struct TemperatureView: View {
    let metrics: [PopupStatusItem]

    var body: some View {
        CardView(title: "温度监控", icon: "thermometer.medium", iconColor: AppTheme.orange) {
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
        CardView(title: "车身状态", icon: "car.fill", iconColor: AppTheme.green) {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Text(dashboard.bodyStatusNormalText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(dashboard.warningMessages.isEmpty ? AppTheme.green : AppTheme.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill((dashboard.warningMessages.isEmpty ? AppTheme.green : AppTheme.orange).opacity(0.12)))
                }
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
