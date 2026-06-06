import SwiftUI

struct QuickActionsView: View {
    @State private var showingCmdAlert = false
    @State private var cmdTitle = ""

    private let actions: [(icon: String, label: String, gradient: [Color])] = [
        ("lock.fill",      "锁车", [Color(red:1,green:0.3,blue:0.3),  Color(red:0.9,green:0.1,blue:0.15)]),
        ("lock.open.fill", "解锁", [Color(red:0.2,green:0.8,blue:0.4), Color(red:0.1,green:0.6,blue:0.3)]),
        ("dot.radiowaves.left.and.right", "启动", [Color(red:1,green:0.6,blue:0.1),   Color(red:1,green:0.4,blue:0.0)]),
        ("location.fill",  "寻车", [Color(red:0.7,green:0.3,blue:0.9), Color(red:0.5,green:0.2,blue:0.8)])
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.label) { action in
                Button(action: {
                    cmdTitle = action.label
                    showingCmdAlert = true
                }) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: action.gradient,
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                                .frame(width: 50, height: 50)
                                .shadow(color: action.gradient[0].opacity(0.3),
                                        radius: 6, x: 0, y: 3)
                            Image(systemName: action.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Text(action.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .darkAlert(
            isPresented: $showingCmdAlert,
            title: cmdTitle,
            message: "确定要\(cmdTitle)吗？",
            confirmTitle: "确认执行",
            confirmColor: AppTheme.accent
        ) { }
    }
}

struct RangeCardView: View {
    var body: some View {
        CardView {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(AppTheme.orange).font(.caption)
                Text("充电中").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("3.2 kW").font(.caption.bold()).foregroundColor(AppTheme.orange)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.orange.opacity(0.1)))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "gauge.medium").foregroundColor(.secondary)
                Text("802").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("km").font(.system(size: 16, weight: .medium)).foregroundColor(.secondary)
            }
            .padding(.top, 4)

            RangeRow(icon: "battery.100.bolt", iconColor: AppTheme.accent,
                     iconBg: AppTheme.accent.opacity(0.12),
                     label: "电量", percent: "52%", percentColor: AppTheme.accent,
                     range: "122 km", barPercent: 0.52, barColor: AppTheme.accent)

            RangeRow(icon: "fuelpump.fill", iconColor: AppTheme.orange,
                     iconBg: AppTheme.orange.opacity(0.12),
                     label: "油量", percent: "78%", percentColor: AppTheme.orange,
                     range: "680 km", barPercent: 0.78, barColor: AppTheme.orange)
        }
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
    private let metrics: [BatterySystemMetric] = [
        BatterySystemMetric(icon: "bolt.fill", label: "动力电压", value: "109.5V", color: AppTheme.accent),
        BatterySystemMetric(icon: "waveform.path.ecg", label: "动力电流", value: "0.0A", color: AppTheme.green),
        BatterySystemMetric(icon: "car.fill", label: "小电瓶", value: "12.4V", color: AppTheme.accent),
        BatterySystemMetric(icon: "checkmark.seal.fill", label: "电池指示", value: "正常", color: AppTheme.green)
    ]

    var body: some View {
        CardView(title: "电池系统", icon: "battery.100.bolt", iconColor: AppTheme.accent) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.green.opacity(0.12))
                            .frame(width: 46, height: 46)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.green)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("电池正常")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("高压系统 / 小电瓶状态正常")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("99%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.green)
                        Text("健康度")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(metrics) { metric in
                        BatterySystemMetricChip(metric: metric)
                    }
                }
            }
        }
    }
}

private struct BatterySystemMetric: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let color: Color
}

private struct BatterySystemMetricChip: View {
    @EnvironmentObject var theme: ThemeManager
    let metric: BatterySystemMetric

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
                Text(metric.value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.cardBg))
    }
}

struct TemperatureView: View {
    private let rows: [TemperatureMetric] = [
        TemperatureMetric(icon: "thermometer", label: "电池最高", value: "25°C", status: "正常", color: AppTheme.green),
        TemperatureMetric(icon: "thermometer", label: "电池最低", value: "25°C", status: "正常", color: AppTheme.green),
        TemperatureMetric(icon: "thermometer", label: "电机温度", value: "27°C", status: "正常", color: AppTheme.green),
        TemperatureMetric(icon: "thermometer", label: "逆变器", value: "27°C", status: "正常", color: AppTheme.green),
        TemperatureMetric(icon: "thermometer", label: "车内温度", value: "22°C", status: "舒适", color: AppTheme.accent),
        TemperatureMetric(icon: "thermometer", label: "空调设定", value: "17°C", status: "设定", color: AppTheme.orange)
    ]

    var body: some View {
        CardView(title: "温度监控", icon: "thermometer.medium", iconColor: AppTheme.orange) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.green.opacity(0.12))
                            .frame(width: 46, height: 46)
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.green)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("电池均温")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("25°C")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("正常")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.green)
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppTheme.green.opacity(0.08)))

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        TemperatureMetricRow(metric: row)
                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }
}

private struct TemperatureMetric: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color
}

private struct TemperatureMetricRow: View {
    let metric: TemperatureMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: metric.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(metric.color)
                .frame(width: 24)

            Text(metric.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Text(metric.value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            Text(metric.status)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(metric.color)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .padding(.vertical, 9)
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
