import SwiftUI
import CoreMotion

// MARK: - Gyroscope Motion Manager
class MotionManager: ObservableObject {
    private let manager = CMMotionManager()
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let m = motion else { return }
            // Smooth the values
            let smooth = 0.15
            self?.pitch = self.map(m.attitude.pitch, smooth: smooth, old: self?.pitch ?? 0)
            self?.roll  = self.map(m.attitude.roll,  smooth: smooth, old: self?.roll  ?? 0)
        }
    }

    private func map(_ new: Double, smooth: Double, old: Double) -> Double {
        return old + smooth * (new - old)
    }

    deinit { manager.stopDeviceMotionUpdates() }
}

// MARK: - Status View (Tab 1)
struct StatusView: View {
    @State private var isRefreshing = false
    @StateObject private var motion = MotionManager()

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    HeaderView(isRefreshing: $isRefreshing)
                    RadarCardView(motion: motion)
                    QuickActionsView()
                    RangeCardView()
                    BatteryGaugesView()
                    TemperatureView()
                    VehicleInfoMergedCard()
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

// MARK: - Radar Card (Real Radar + Gyroscope)
struct RadarCardView: View {
    @ObservedObject var motion: MotionManager
    @State private var rssi: Int = -42
    @State private var sweepAngle: Double = 0
    @State private var radarSize: CGFloat = 220

    // RSSI → normalized 0(center)…1(edge)
    private var signalNorm: Double {
        let clamped = max(-110, min(-30, rssi))
        return Double(-30 - clamped) / 80.0
    }

    // Car size: strong signal → big, weak → small
    private var carSize: CGFloat {
        CGFloat(70 - signalNorm * 40) // 70 → 30
    }

    // Car offset from center: strong → near center, weak → far
    private var carOffset: CGFloat {
        let maxR = radarSize / 2 - 40
        return CGFloat(signalNorm) * maxR * 0.6
    }

    var body: some View {
        VStack(spacing: 16) {
            // Radar circle
            ZStack {
                // Background circle
                Circle()
                    .fill(Color(.systemGray6).opacity(0.5))
                    .frame(width: radarSize, height: radarSize)

                // 3 concentric rings
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.08 + Double(i) * 0.03), lineWidth: 1)
                        .frame(width: radarSize * CGFloat(i) / 3.0,
                               height: radarSize * CGFloat(i) / 3.0)
                }

                // Cross lines
                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(AppTheme.accent.opacity(0.06))
                        .frame(width: 1, height: radarSize)
                        .rotationEffect(.degrees(Double(i) * 45))
                }

                // Radar sweep fan (gradient tail)
                RadarSweepShape()
                    .fill(
                        AngularGradient(
                            colors: [
                                AppTheme.accent.opacity(0),
                                AppTheme.accent.opacity(0.02),
                                AppTheme.accent.opacity(0.08),
                                AppTheme.accent.opacity(0.18)
                            ],
                            center: .center,
                            startAngle: .degrees(-50),
                            endAngle: .degrees(0)
                        )
                    )
                    .frame(width: radarSize, height: radarSize)
                    .rotationEffect(.degrees(sweepAngle))

                // Sweep line
                Rectangle()
                    .fill(AppTheme.accent.opacity(0.6))
                    .frame(width: 1.5, height: radarSize / 2)
                    .offset(y: -radarSize / 4)
                    .rotationEffect(.degrees(sweepAngle))

                // Car icon — position based on signal
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.15))
                            .frame(width: carSize, height: carSize)
                        // 可替换为 Image("car") 使用 PNG 车图
                        Image(systemName: "car.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: carSize * 0.5, height: carSize * 0.5)
                            .foregroundColor(AppTheme.accent)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 8)
                }
                .offset(x: carOffset * 0.7, y: carOffset * 0.7) // move diagonally
                .animation(.easeInOut(duration: 1.5), value: rssi)
            }
            .frame(width: radarSize, height: radarSize)
            // Gyroscope 3D tilt effect
            .rotation3DEffect(
                .degrees(motion.pitch * 8),
                axis: (x: 1, y: 0, z: 0)
            )
            .rotation3DEffect(
                .degrees(motion.roll * 8),
                axis: (x: 0, y: 1, z: 0)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                    sweepAngle = 360
                }
            }

            // RSSI value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(rssi)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)
                Text("dBm")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Status pills
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

// MARK: - Radar Sweep Fan Shape
struct RadarSweepShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(-50), endAngle: .degrees(0),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Quick Actions
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
                    .foregroundColor(AppTheme.orange).font(.caption)
                Text("充电中").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("3.2 kW").font(.caption.bold()).foregroundColor(AppTheme.orange)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.orange.opacity(0.1)))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "gauge.medium").foregroundColor(.secondary)
                Text("1140").font(.system(size: 38, weight: .bold, design: .rounded))
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
                    RoundedRectangle(cornerRadius: 6).fill(iconBg).frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(iconColor)
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
                RoundedRectangle(cornerRadius: 8).fill(item.color.opacity(0.1)).frame(width: 36, height: 36)
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Vehicle Info Merged Card (Collapsible + Long Press Copy)
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

    // Full text for copy
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
