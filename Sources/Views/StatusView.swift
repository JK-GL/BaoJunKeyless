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
            guard let self = self, let m = motion else { return }
            let smooth = 0.15
            self.pitch += smooth * (m.attitude.pitch - self.pitch)
            self.roll  += smooth * (m.attitude.roll  - self.roll)
        }
    }

    deinit { manager.stopDeviceMotionUpdates() }
}

// MARK: - Status View (Tab 1)
struct StatusView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @StateObject private var motion = MotionManager()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "宝骏云海")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                RadarCardView(motion: motion)
                QuickActionsView()
                RangeCardView()
                BatteryGaugesView()
                TemperatureView()
                VehicleInfoMergedCard()

                Spacer(minLength: 100)
            }
        }
        .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
        .onDisappear {
            scrollState.reset()
        }
    }
}

// MARK: - Radar UIView (redesigned, car fixed, dynamic RSSI)

// MARK: - Radar UIView (Holographic HUD style)
class RadarUIView: UIView {
    private let sz: CGFloat = 280
    private var sweep: CGFloat = 0
    private var rssi: Double = -42
    private var targetRssi: Double = -42
    private var pitch: Double = 0
    private var roll: Double = 0
    private var link: CADisplayLink?
    private var t0: CFTimeInterval = 0
    private var sigTimer: Timer?
    var onRssiChange: ((Double) -> Void)?

    private var carSz: CGFloat = 70
    private var carX: CGFloat = 0
    private var carY: CGFloat = 0

    // Blue palette
    private let blue1 = UIColor(red: 0.15, green: 0.50, blue: 0.95, alpha: 1)
    private let blue2 = UIColor(red: 0.20, green: 0.60, blue: 1.00, alpha: 1)
    private let blue3 = UIColor(red: 0.40, green: 0.78, blue: 1.00, alpha: 1)

    // Pre-rendered wireframe car
    private var carOutline: UIImage? = { () -> UIImage? in
        let s: CGFloat = 200
        UIGraphicsBeginImageContextWithOptions(CGSize(width: s, height: s), false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let carColor = UIColor.label.withAlphaComponent(0.6)
        ctx.setStrokeColor(carColor.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Car wireframe (front-view SUV)
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 45, y: 130))
        p.addLine(to: CGPoint(x: 45, y: 100))
        p.addCurve(to: CGPoint(x: 55, y: 75), controlPoint1: CGPoint(x: 45, y: 85), controlPoint2: CGPoint(x: 48, y: 75))
        p.addLine(to: CGPoint(x: 72, y: 48))
        p.addCurve(to: CGPoint(x: 100, y: 38), controlPoint1: CGPoint(x: 78, y: 42), controlPoint2: CGPoint(x: 88, y: 38))
        p.addLine(to: CGPoint(x: 108, y: 38))
        p.addLine(to: CGPoint(x: 128, y: 38))
        p.addCurve(to: CGPoint(x: 145, y: 48), controlPoint1: CGPoint(x: 138, y: 38), controlPoint2: CGPoint(x: 142, y: 42))
        p.addLine(to: CGPoint(x: 155, y: 75))
        p.addCurve(to: CGPoint(x: 165, y: 100), controlPoint1: CGPoint(x: 162, y: 75), controlPoint2: CGPoint(x: 165, y: 85))
        p.addLine(to: CGPoint(x: 165, y: 130))
        p.close()
        p.stroke()

        // Headlights
        let ll = UIBezierPath(arcCenter: CGPoint(x: 62, y: 108), radius: 8, startAngle: 0, endAngle: .pi*2, clockwise: true)
        let rl = UIBezierPath(arcCenter: CGPoint(x: 148, y: 108), radius: 8, startAngle: 0, endAngle: .pi*2, clockwise: true)
        ll.stroke(); rl.stroke()

        // Grille lines
        let g = UIBezierPath()
        g.move(to: CGPoint(x: 80, y: 100)); g.addLine(to: CGPoint(x: 128, y: 100))
        g.move(to: CGPoint(x: 80, y: 112)); g.addLine(to: CGPoint(x: 128, y: 112))
        g.stroke()

        // Windshield dividers
        let d = UIBezierPath()
        d.move(to: CGPoint(x: 100, y: 42)); d.addLine(to: CGPoint(x: 100, y: 75))
        d.move(to: CGPoint(x: 108, y: 38)); d.addLine(to: CGPoint(x: 108, y: 75))
        d.stroke()

        // Headlight glow
        ctx.setFillColor(UIColor(red: 0.20, green: 0.45, blue: 0.70, alpha: 0.2).cgColor)
        ctx.fillEllipse(in: CGRect(x: 52, y: 98, width: 20, height: 20))
        ctx.fillEllipse(in: CGRect(x: 138, y: 98, width: 20, height: 20))

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }()

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        isOpaque = false; backgroundColor = .clear
        t0 = CACurrentMediaTime()
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        sigTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.targetRssi = Double(Int.random(in: -85 ... -35))
        }
    }

    @objc private func tick() {
        sweep = CGFloat(fmod((CACurrentMediaTime() - t0) / 3.0, 1.0)) * 360.0
        let old = rssi
        rssi += (targetRssi - rssi) * 0.06
        if abs(rssi - old) > 0.3 {
            DispatchQueue.main.async { self.onRssiChange?(self.rssi) }
        }
        setNeedsDisplay()
    }

    func updateGyro(pitch: Double, roll: Double) { self.pitch = pitch; self.roll = roll }
    deinit { link?.invalidate(); sigTimer?.invalidate() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = rect.midX, cy = rect.midY, r = sz / 2
        let cs = CGColorSpaceCreateDeviceRGB()
        let rad = sweep * .pi / 180

        // ── 1. Transparent background (no fill) ──
        // Radar is transparent — only lines and sweep are drawn

        // ── 2. Tick marks ──
        let tickColor = UIColor.label.withAlphaComponent(1)
        for deg in 0..<360 {
            let a = CGFloat(deg) * .pi / 180
            let major = deg % 30 == 0
            let mid = deg % 10 == 0
            let inner: CGFloat = major ? r - 18 : (mid ? r - 11 : r - 7)
            let alpha: Double = major ? 0.45 : (mid ? 0.2 : 0.08)
            let w: CGFloat = major ? 1.5 : (mid ? 0.8 : 0.3)
            ctx.setStrokeColor(tickColor.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(w)
            ctx.move(to: .init(x: cx + inner * cos(a), y: cy + inner * sin(a)))
            ctx.addLine(to: .init(x: cx + (r - 1) * cos(a), y: cy + (r - 1) * sin(a)))
            ctx.strokePath()
        }

        // ── 3. Outer ring ──
        ctx.setStrokeColor(tickColor.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: .init(x: cx-r+1, y: cy-r+1, width: (r-1)*2, height: (r-1)*2))

        // ── 4. Inner rings ──
        for i in 1...3 {
            let rr = r * CGFloat(i) / 3.5
            ctx.setStrokeColor(tickColor.withAlphaComponent(0.04 + Double(i)*0.02).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: .init(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2))
        }

        // ── 5. Cross-hair ──
        ctx.setStrokeColor(tickColor.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: .init(x:cx,y:cy-r+14)); ctx.addLine(to: .init(x:cx,y:cy+r-14))
        ctx.move(to: .init(x:cx-r+14,y:cy)); ctx.addLine(to: .init(x:cx+r-14,y:cy))
        ctx.strokePath()

        // ── 6. Sweep ──
        ctx.saveGState()
        ctx.addEllipse(in: .init(x: cx-r, y: cy-r, width: r*2, height: r*2))
        ctx.clip()

        // Center glow
        if let g = CGGradient(colorsSpace: cs, colors: [
            UIColor.systemBlue.withAlphaComponent(0.06).cgColor, UIColor.clear.cgColor
        ] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: .init(x:cx,y:cy), startRadius: 0,
                                   endCenter: .init(x:cx,y:cy), endRadius: r*0.5, options: [])
        }

        // Sweep trail
        let fan: CGFloat = 60 * .pi / 180
        for i in 0..<30 {
            let frac = CGFloat(i) / 30
            let a1 = rad - fan * (1 - frac)
            let a2 = rad - fan * (1 - frac - 1.0/30)
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(Double(1 - frac) * 0.12).cgColor)
            ctx.move(to: .init(x: cx, y: cy))
            ctx.addArc(center: .init(x:cx,y:cy), radius: r, startAngle: a1, endAngle: a2, clockwise: false)
            ctx.closePath(); ctx.fillPath()
        }

        // Sweep line
        let end = CGPoint(x: cx + r * 1.05 * cos(rad), y: cy + r * 1.05 * sin(rad))
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(6); ctx.setLineCap(.round)
        ctx.move(to: .init(x:cx,y:cy)); ctx.addLine(to: end); ctx.strokePath()
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.2)
        ctx.move(to: .init(x:cx,y:cy)); ctx.addLine(to: end); ctx.strokePath()

        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.6).cgColor)
        ctx.fillEllipse(in: .init(x: cx-2, y: cy-2, width: 4, height: 4))
        ctx.restoreGState()

        // ── 7. Car wireframe ──
        let n = (-30 - max(-110, min(-30, rssi))) / 80.0
        let tSz: CGFloat = sz * (0.32 - 0.20 * CGFloat(n))
        let tOff = CGFloat(n) * (r - tSz/2 - 15)
        carSz += (tSz - carSz) * 0.05
        let tx = cx + tOff * 0.7071 + CGFloat(roll) * 3
        let ty = cy + tOff * 0.7071 + CGFloat(pitch) * 3
        carX += (tx - carX) * 0.05
        carY += (ty - carY) * 0.05

        // Glow halo
        let glowR = carSz * 0.7
        if let g = CGGradient(colorsSpace: cs, colors: [
            UIColor.systemBlue.withAlphaComponent(0.08).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.02).cgColor,
            UIColor.clear.cgColor
        ] as CFArray, locations: [0, 0.5, 1]) {
            ctx.drawRadialGradient(g, startCenter: .init(x:carX,y:carY), startRadius: 0,
                                   endCenter: .init(x:carX,y:carY), endRadius: glowR, options: [])
        }

        // Wireframe car
        let half = carSz / 2
        carOutline?.draw(in: CGRect(x: carX - half, y: carY - half, width: carSz, height: carSz))
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }
}

// MARK: - SwiftUI Wrapper
struct RadarCardView: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var motion: MotionManager
    @State private var rssiText = "-42 dBm"
    private let radar = RadarUIView(frame: .zero)

    var body: some View {
        VStack(spacing: 12) {
            // Radar with dBm pill overlay in center
            ZStack {
                RadarRepresentable(motion: motion, radar: radar)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())

                // dBm text — center, transparent bg
                HStack(spacing: 3) {
                    Text(rssiText.replacingOccurrences(of: " dBm", with: ""))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    Text("dBm")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.textSecondary)
            }

            // Status pills
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    StatusPill(icon: "shield.fill", text: "密钥正常", color: AppTheme.green)
                    StatusPill(icon: "bolt.fill", text: "蓝牙已连接", color: AppTheme.green)
                }
                HStack(spacing: 8) {
                    StatusPill(icon: "arrow.triangle.2.circlepath", text: "全程接管", color: AppTheme.purple)
                    StatusPill(icon: "lock.open.fill", text: "未锁车", color: AppTheme.orange)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .onAppear {
            radar.onRssiChange = { val in
                DispatchQueue.main.async { rssiText = String(format: "%.0f dBm", val) }
            }
        }
    }
}

struct RadarRepresentable: UIViewRepresentable {
    @ObservedObject var motion: MotionManager
    let radar: RadarUIView
    func makeUIView(context: Context) -> RadarUIView { radar }
    func updateUIView(_ v: RadarUIView, context: Context) {
        v.updateGyro(pitch: motion.pitch, roll: motion.roll)
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
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.orange.opacity(0.1)))

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
