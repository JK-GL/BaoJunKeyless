import SwiftUI

// MARK: - Status View (Tab 1)
struct StatusView: View {
    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    HeaderView(isRefreshing: $isRefreshing)
                    RadarCardView()
                    QuickActionsView()
                    RangeCardView()
                    BatteryGaugesView()
                    TemperatureView()
                    VehicleStatusView()
                    BLEKeyInfoView()
                    Spacer(minLength: 20)
                }
                .padding(.bottom, 10)
            }
            .background(AppTheme.pageBg.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Header
struct HeaderView: View {
    @Binding var isRefreshing: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("宝骏云海")
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.green)
                        .frame(width: 8, height: 8)
                    Text("BLE 已连接")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.5)) { isRefreshing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { isRefreshing = false }
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Radar Card
struct RadarCardView: View {
    @State private var rssi: Int = -42
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.15 / Double(i)), lineWidth: 1.5)
                        .frame(width: CGFloat(60 + i * 40), height: CGFloat(60 + i * 40))
                }
                Circle()
                    .stroke(AppTheme.accent.opacity(0.3), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
                    .animation(
                        Animation.easeInOut(duration: 2).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: "car.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.accent)
                }
            }
            .frame(height: 180)
            .onAppear { pulseScale = 1.3 }

            Text("\(rssi) dBm")
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundColor(AppTheme.accent)

            HStack(spacing: 8) {
                StatusPill(icon: "shield.fill", text: "密钥正常", color: AppTheme.green)
                StatusPill(icon: "bolt.fill", text: "蓝牙已连接", color: AppTheme.green)
            }
            HStack(spacing: 8) {
                StatusPill(icon: "arrow.triangle.2.circlepath", text: "全程接管", color: AppTheme.purple)
                StatusPill(icon: "lock.open.fill", text: "未锁车", color: AppTheme.orange)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.cardBg)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Quick Actions
struct QuickActionsView: View {
    @State private var showingCmdAlert = false
    @State private var cmdTitle = ""

    private let actions: [(icon: String, label: String, gradient: [Color])] = [
        ("lock.fill",          "锁车", [Color(red:1,green:0.3,blue:0.3), Color(red:0.9,green:0.1,blue:0.15)]),
        ("lock.open.fill",     "解锁", [Color(red:0.2,green:0.8,blue:0.4), Color(red:0.1,green:0.6,blue:0.3)]),
        ("bolt.fill",          "启动", [Color(red:1,green:0.6,blue:0.1), Color(red:1,green:0.4,blue:0.0)]),
        ("location.fill",      "寻车", [Color(red:0.7,green:0.3,blue:0.9), Color(red:0.5,green:0.2,blue:0.8)])
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
        .alert(cmdTitle, isPresented: $showingCmdAlert) {
            Button("取消", role: .cancel) { }
            Button("确认执行") { }
        } message: {
            Text("确定要\(cmdTitle)吗？")
        }
    }
}

// MARK: - Range Card
struct RangeCardView: View {
    var body: some View {
        CardView {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(AppTheme.orange)
                    .font(.caption)
                Text("充电中").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("3.2 kW").font(.caption.bold()).foregroundColor(AppTheme.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.orange.opacity(0.1)))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "gauge.medium").foregroundColor(.secondary)
                Text("1140")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("km")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
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
                    RoundedRectangle(cornerRadius: 6).fill(iconBg).frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Text(label).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
                Text(percent).font(.system(size: 14, weight: .bold)).foregroundColor(percentColor)
                Spacer()
                Text(range).font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [barColor.opacity(0.8), barColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * barPercent, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Battery Gauges
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
    let item: GaugeItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 6)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: item.percent)
                    .stroke(AngularGradient(colors: [item.color.opacity(0.3), item.color],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(item.value)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(item.maxValue)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 10))
                    .foregroundColor(item.color)
                Text(item.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Temperature
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
    let item: TempItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.color.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(item.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 12)).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text(item.status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(item.color)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Vehicle Status
struct VehicleStatusView: View {
    private let items: [StatusItem] = [
        StatusItem(icon: "door.left.hand.open", label: "车门", value: "全部关闭", color: .green),
        StatusItem(icon: "car.side",             label: "车窗", value: "全部关闭", color: .green),
        StatusItem(icon: "engine.combustion",    label: "引擎", value: "已熄火",   color: .secondary),
        StatusItem(icon: "car.top.radiowaves.rear.right", label: "天窗", value: "已关闭", color: .green),
        StatusItem(icon: "lightbulb.fill",       label: "车灯", value: "已关闭",   color: .secondary),
        StatusItem(icon: "hand.raised.fill",     label: "手刹", value: "已拉起",   color: .green)
    ]

    var body: some View {
        CardView(title: "车辆状态", icon: "car.fill", iconColor: AppTheme.accent) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(items) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                            .foregroundColor(item.color)
                            .frame(height: 24)
                        Text(item.label)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                        Text(item.value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(item.color)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
                }
            }
        }
    }
}

// MARK: - BLE Key Info
struct BLEKeyInfoView: View {
    private let items: [KeyInfoItem] = [
        KeyInfoItem(icon: "key.fill", label: "钥匙类型", value: "车主钥匙"),
        KeyInfoItem(icon: "wave.3.right", label: "BLE 设备", value: "E260-BLE"),
        KeyInfoItem(icon: "antenna.radiowaves.left.and.right", label: "MAC", value: "CC:45:A5:DA:B5:C3"),
        KeyInfoItem(icon: "number", label: "Key ID", value: "1123037"),
        KeyInfoItem(icon: "person.fill", label: "提供商", value: "德赛 (desai)"),
        KeyInfoItem(icon: "shield.checkered", label: "状态", value: "有效")
    ]

    var body: some View {
        CardView(title: "BLE 钥匙", icon: "key.fill", iconColor: AppTheme.accent) {
            Text("从五菱汽车 APP 自动读取")
                .font(.caption).foregroundColor(.secondary).padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14)).foregroundColor(.secondary).frame(width: 20)
                        Text(item.label)
                            .font(.system(size: 14)).foregroundColor(.secondary)
                        Spacer()
                        Text(item.value)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 10)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 30)
                    }
                }
            }
        }
    }
}
