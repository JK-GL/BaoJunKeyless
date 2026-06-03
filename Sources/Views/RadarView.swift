import SwiftUI
import UIKit

// MARK: - 声波涟漪雷达（无指针，同心圆扩散）

// MARK: - 星空粒子
struct StarParticle {
    var x: Double
    var y: Double
    var size: Double
    var alpha: Double
    var speed: Double
    var phase: Double
}

// MARK: - 波纹
struct WaveRing {
    var radius: CGFloat       // 当前半径
    var maxRadius: CGFloat    // 最大半径
    var life: Double          // 0→1 进度
    var speed: Double         // 扩散速度
    var lineWidth: CGFloat    // 线宽
}

// MARK: - 声波雷达 UIView
class RadarUIView: UIView {
    private let sz: CGFloat = 280
    private var rssi: Double = -42
    private var targetRssi: Double = -42
    private var pitch: Double = 0
    private var roll: Double = 0
    private var link: CADisplayLink?
    private var lastWaveTime: CFTimeInterval = 0
    private var sigTimer: Timer?
    var onRssiChange: ((Double) -> Void)?

    private var carSz: CGFloat = 70
    private var carX: CGFloat = 0
    private var carY: CGFloat = 0

    // 静态缓存
    private var staticCache: UIImage?
    private var lastCacheSize: CGSize = .zero

    // 星空粒子
    private var stars: [StarParticle] = []

    // ⭐ 波纹队列
    private var waves: [WaveRing] = []
    private let waveInterval: Double = 1.2  // 每 1.2 秒产生一个新波纹
    private let maxWaves: Int = 5           // 最多同时显示 5 个波纹

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        isOpaque = false; backgroundColor = .clear
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
        sigTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.targetRssi = Double(Int.random(in: -85 ... -35))
        }
        generateStars()
    }

    private func generateStars() {
        stars = (0..<60).map { _ in
            StarParticle(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 0.5...2.0),
                alpha: Double.random(in: 0.03...0.15),
                speed: Double.random(in: 0.5...2.0),
                phase: Double.random(in: 0...(2 * .pi))
            )
        }
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()

        // 更新 RSSI
        let old = rssi
        rssi += (targetRssi - rssi) * 0.06
        if abs(rssi - old) > 0.3 {
            DispatchQueue.main.async { self.onRssiChange?(self.rssi) }
        }

        // ⭐ 定期产生新波纹
        if now - lastWaveTime >= waveInterval {
            let r = sz / 2
            waves.append(WaveRing(
                radius: 0,
                maxRadius: r,
                life: 0,
                speed: Double(r) / 2.0,  // 2 秒扩散到最大
                lineWidth: 2.0
            ))
            lastWaveTime = now
        }

        // ⭐ 更新波纹
        let dt = 1.0 / 60.0
        for i in waves.indices {
            waves[i].life += dt / 2.0  // 2 秒完成
            waves[i].radius = waves[i].maxRadius * CGFloat(waves[i].life)
            waves[i].lineWidth = 2.0 * CGFloat(1 - waves[i].life)  // 越远越细
        }
        waves.removeAll { $0.life >= 1.0 }

        setNeedsDisplay()
    }

    func updateGyro(pitch: Double, roll: Double) { self.pitch = pitch; self.roll = roll }
    deinit { link?.invalidate(); sigTimer?.invalidate() }

    // 静态元素缓存
    private func buildStaticCache(_ size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = size.width / 2, cy = size.height / 2, r = sz / 2
        let tickColor = UIColor.label.withAlphaComponent(1)

        // 刻度
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

        // 外环
        ctx.setStrokeColor(tickColor.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: .init(x: cx-r+1, y: cy-r+1, width: (r-1)*2, height: (r-1)*2))

        // 内环
        for i in 1...3 {
            let rr = r * CGFloat(i) / 3.5
            ctx.setStrokeColor(tickColor.withAlphaComponent(0.04 + Double(i)*0.02).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: .init(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2))
        }

        // 十字线
        ctx.setStrokeColor(tickColor.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: .init(x:cx,y:cy-r+14)); ctx.addLine(to: .init(x:cx,y:cy+r-14))
        ctx.move(to: .init(x:cx-r+14,y:cy)); ctx.addLine(to: .init(x:cx+r-14,y:cy))
        ctx.strokePath()

        // 星空粒子
        let now = CACurrentMediaTime()
        for star in stars {
            let sx = CGFloat(star.x) * size.width
            let sy = CGFloat(star.y) * size.height
            let twinkle = (sin(now * star.speed + star.phase) + 1) / 2
            let alpha = star.alpha * (0.3 + 0.7 * twinkle)
            ctx.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: sx - star.size/2, y: sy - star.size/2, width: star.size, height: star.size))
        }

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        staticCache = result
        lastCacheSize = size
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = rect.midX, cy = rect.midY, r = sz / 2
        let cs = CGColorSpaceCreateDeviceRGB()

        // 绘制缓存的静态元素
        if staticCache == nil || lastCacheSize != bounds.size {
            buildStaticCache(bounds.size)
        }
        staticCache?.draw(at: .zero)

        // 裁剪到圆形区域
        ctx.saveGState()
        ctx.addEllipse(in: .init(x: cx-r, y: cy-r, width: r*2, height: r*2))
        ctx.clip()

        // 中心发光
        if let g = CGGradient(colorsSpace: cs, colors: [
            UIColor.systemBlue.withAlphaComponent(0.06).cgColor, UIColor.clear.cgColor
        ] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: .init(x:cx,y:cy), startRadius: 0,
                                   endCenter: .init(x:cx,y:cy), endRadius: r*0.4, options: [])
        }

        // ⭐ 绘制波纹
        for wave in waves {
            let alpha = CGFloat(1 - wave.life) * 0.6  // 越远越淡
            let lineWidth = max(wave.lineWidth, 0.5)

            // 外层光晕
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(Double(alpha * 0.3)).cgColor)
            ctx.setLineWidth(lineWidth + 4)
            ctx.strokeEllipse(in: .init(
                x: cx - wave.radius, y: cy - wave.radius,
                width: wave.radius * 2, height: wave.radius * 2
            ))

            // 内层亮线
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(Double(alpha)).cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: .init(
                x: cx - wave.radius, y: cy - wave.radius,
                width: wave.radius * 2, height: wave.radius * 2
            ))
        }

        // 中心点
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.8).cgColor)
        ctx.fillEllipse(in: .init(x: cx-4, y: cy-4, width: 8, height: 8))

        // 中心光圈
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: .init(x: cx-10, y: cy-10, width: 20, height: 20))

        ctx.restoreGState()

        // ── 车辆图标 ──
        let n = (-30 - max(-110, min(-30, rssi))) / 80.0
        let tSz: CGFloat = sz * (0.32 - 0.20 * CGFloat(n))
        let tOff = CGFloat(n) * (r - tSz/2 - 15)
        carSz += (tSz - carSz) * 0.05
        let tx = cx + tOff * 0.7071 + CGFloat(roll) * 3
        let ty = cy + tOff * 0.7071 + CGFloat(pitch) * 3
        carX += (tx - carX) * 0.05
        carY += (ty - carY) * 0.05

        // 车辆发光光晕
        let glowR = carSz * 0.7
        if let g = CGGradient(colorsSpace: cs, colors: [
            UIColor.systemBlue.withAlphaComponent(0.12).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.04).cgColor,
            UIColor.clear.cgColor
        ] as CFArray, locations: [0, 0.5, 1]) {
            ctx.drawRadialGradient(g, startCenter: .init(x:carX,y:carY), startRadius: 0,
                                   endCenter: .init(x:carX,y:carY), endRadius: glowR, options: [])
        }

        // SF Symbol car.fill
        let config = UIImage.SymbolConfiguration(pointSize: carSz * 0.6, weight: .medium)
        if let symbolImage = UIImage(systemName: "car.fill", withConfiguration: config) {
            let tinted = symbolImage.withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
            let drawRect = CGRect(
                x: carX - tinted.size.width / 2,
                y: carY - tinted.size.height / 2,
                width: tinted.size.width,
                height: tinted.size.height
            )
            tinted.draw(in: drawRect)
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }
}

// MARK: - SwiftUI 封装
struct RadarRepresentable: UIViewRepresentable {
    @ObservedObject var motion: MotionManager
    let radar: RadarUIView
    func makeUIView(context: Context) -> RadarUIView { radar }
    func updateUIView(_ v: RadarUIView, context: Context) {
        v.updateGyro(pitch: motion.pitch, roll: motion.roll)
    }
}

// MARK: - Radar Card
struct RadarCardView: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var motion: MotionManager
    @State private var rssiText = "-42 dBm"
    @State private var rssiValue: Double = -42
    private let radar = RadarUIView(frame: .zero)

    private var rssiColor: Color {
        let strength = max(0, min(1, (rssiValue + 110) / 80))
        if strength > 0.6 {
            return Color(red: 0.2, green: 0.6, blue: 1.0)
        } else if strength > 0.3 {
            return Color(red: 1.0, green: 0.7, blue: 0.2)
        } else {
            return Color(red: 1.0, green: 0.3, blue: 0.2)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RadarRepresentable(motion: motion, radar: radar)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())

                HStack(spacing: 3) {
                    Text(rssiText.replacingOccurrences(of: " dBm", with: ""))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    Text("dBm")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(rssiColor)
            }

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
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .onAppear {
            radar.onRssiChange = { val in
                DispatchQueue.main.async {
                    rssiText = String(format: "%.0f dBm", val)
                    rssiValue = val
                }
            }
        }
    }
}
