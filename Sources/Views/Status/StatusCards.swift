import SwiftUI

struct QuickActionsView: View {
    @State private var showingCmdAlert = false
    @State private var cmdTitle = ""

    private let actions: [(icon: String, label: String, gradient: [Color])] = [
        ("lock.fill",      "锁车", [Color(red:1,green:0.3,blue:0.3),  Color(red:0.9,green:0.1,blue:0.15)]),
        ("lock.open.fill", "解锁", [Color(red:0.2,green:0.8,blue:0.4), Color(red:0.1,green:0.6,blue:0.3)]),
        ("bolt.fill",      "启动", [Color(red:1,green:0.6,blue:0.1),   Color(red:1,green:0.4,blue:0.0)]),
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
    private let gauges: [GaugeItem] = [
        GaugeItem(icon: "bolt.fill", label: "电池电压", value: "386.2", maxValue: "420V", percent: 0.92, color: .blue),
        GaugeItem(icon: "bolt.fill", label: "电池电流", value: "24.5", maxValue: "150A", percent: 0.16, color: .green),
        GaugeItem(icon: "battery.100", label: "SOH", value: "98.2", maxValue: "100%", percent: 0.982, color: .purple),
        GaugeItem(icon: "thermometer.medium", label: "电池温度", value: "32", maxValue: "60°C", percent: 0.53, color: .orange)
    ]

    var body: some View {
        CardView(title: "电池仪表", icon: "bolt.fill", iconColor: AppTheme.accent) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(gauges) { GaugeCard(item: $0) }
            }
        }
    }
}

struct GaugeCard: View {
    @EnvironmentObject var theme: ThemeManager
    let item: GaugeItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 6).frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: item.percent)
                    .stroke(AngularGradient(colors: [item.color.opacity(0.3), item.color], center: .center),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(item.value).font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(item.maxValue).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: item.icon).font(.system(size: 10)).foregroundColor(item.color)
                Text(item.label).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.cardBg))
    }
}

struct TemperatureView: View {
    private let temps: [TempItem] = [
        TempItem(icon: "thermometer", label: "电池包", value: "32°C", status: "正常", color: .green),
        TempItem(icon: "thermometer", label: "电机",   value: "45°C", status: "正常", color: .green),
        TempItem(icon: "thermometer", label: "控制器", value: "38°C", status: "正常", color: .green),
        TempItem(icon: "thermometer", label: "充电口", value: "28°C", status: "正常", color: .green)
    ]

    var body: some View {
        CardView(title: "温度监控", icon: "thermometer.medium", iconColor: AppTheme.orange) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(temps) { TempCard(item: $0) }
            }
        }
    }
}

struct TempCard: View {
    @EnvironmentObject var theme: ThemeManager
    let item: TempItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(item.color.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: item.icon).font(.system(size: 14, weight: .medium)).foregroundColor(item.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).font(.system(size: 12)).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(item.value).font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(item.status).font(.system(size: 10, weight: .medium)).foregroundColor(item.color)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.cardBg))
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
