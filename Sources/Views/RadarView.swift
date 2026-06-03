import SwiftUI
import UIKit

// MARK: - 雷达优化版（星空粒子 + 信号渐变 + 扫描粒子 + 静态缓存）

// MARK: - 星空粒子
struct StarParticle {
    var x: Double
    var y: Double
    var size: Double
    var alpha: Double
    var speed: Double  // 闪烁速度
    var phase: Double  // 闪烁相位
}

// MARK: - 扫描粒子
struct SweepParticle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double       // 剩余生命
    var maxLife: Double
    var size: Double
}

// MARK: - 优化版雷达 UIView
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

    // ⭐ #30: 静态元素缓存
    private var staticCache: UIImage?
    private var lastCacheSize: CGSize = .zero

    // ⭐ #7: 星空粒子
    private var stars: [StarParticle] = []

    // ⭐ #29: 扫描粒子
    private var sweepParticles: [SweepParticle] = []
    private var lastSweepAngle: CGFloat = 0

    // 预渲染车辆轮廓
    private var carOutline: UIImage? = { () -> UIImage? in
        let s: CGFloat = 200
        UIGraphicsBeginImageContextWithOptions(CGSize(width: s, height: s), false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let carColor = UIColor.label.withAlphaComponent(0.7)
        ctx.setStrokeColor(carColor.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

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

        let ll = UIBezierPath(arcCenter: CGPoint(x: 62, y: 108), radius: 8, startAngle: 0, endAngle: .pi*2, clockwise: true)
        let rl = UIBezierPath(arcCenter: CGPoint(x: 148, y: 108), radius: 8, startAngle: 0, endAngle: .pi*2, clockwise: true)
        ll.stroke(); rl.stroke()

        let g = UIBezierPath()
        g.move(to: CGPoint(x: 80, y: 100)); g.addLine(to: CGPoint(x: 128, y: 100))
        g.move(to: CGPoint(x: 80, y: 112)); g.addLine(to: CGPoint(x: 128, y: 112))
        g.stroke()

        let d = UIBezierPath()
        d.move(to: CGPoint(x: 100, y: 42)); d.addLine(to: CGPoint(x: 100, y: 75))
        d.move(to: CGPoint(x: 108, y: 38)); d.addLine(to: CGPoint(x: 108, y: 75))
        d.stroke()

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
        generateStars()
    }

    // ⭐ #7: 生成星空粒子
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
        sweep = CGFloat(fmod((now - t0) / 3.0, 1.0)) * 360.0
        let old = rssi
        rssi += (targetRssi - rssi) * 0.06
        if abs(rssi - old) > 0.3 {
            DispatchQueue.main.async { self.onRssiChange?(self.rssi) }
        }

        // ⭐ #29: 在扫描线位置生成粒子
        let rad = sweep * .pi / 180
        let angleDiff = abs(sweep - lastSweepAngle)
        if angleDiff > 2 || angleDiff > 358 {
            let r = sz / 2
            let cx = bounds.midX, cy = bounds.midY
            for _ in 0..<3 {
                let dist = Double.random(in: 30...Double(r - 10))
                let px = cx + CGFloat(dist) * cos(rad)
                let py = cy + CGFloat(dist) * sin(rad)
                let speed = Double.random(in: 15...40)
                let angle = Double.random(in: 0...(2 * .pi))
                sweepParticles.append(SweepParticle(
                    x: Double(px), y: Double(py),
                    vx: cos(angle) * speed, vy: sin(angle) * speed,
                    life: 0.6, maxLife: 0.6,
                    size: Double.random(in: 1.0...2.5)
                ))
            }
            lastSweepAngle = sweep
        }

        // 更新粒子生命
        let dt = 1.0 / 60.0
        sweepParticles.removeAll { $0.life <= 0 }
        for i in sweepParticles.indices {
            sweepParticles[i].x += sweepParticles[i].vx * dt
            sweepParticles[i].y += sweepParticles[i].vy * dt
            sweepParticles[i].life -= dt
        }

        setNeedsDisplay()
    }

    func updateGyro(pitch: Double, roll: Double) { self.pitch = pitch; self.roll = roll }
    deinit { link?.invalidate(); sigTimer?.invalidate() }

    // ⭐ #30: 生成静态元素缓存
    private func buildStaticCache(_ size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = size.width / 2, cy = size.height / 2, r = sz / 2
        let cs = CGColorSpaceCreateDeviceRGB()
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

        // ⭐ #7: 星空粒子
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
        let rad = sweep * .pi / 180

        // ⭐ #30: 绘制缓存的静态元素
        if staticCache == nil || lastCacheSize != bounds.size {
            buildStaticCache(bounds.size)
        }
        staticCache?.draw(at: .zero)

        // ── 扫描动画（动态层）──
        ctx.saveGState()
        ctx.addEllipse(in: .init(x: cx-r, y: cy-r, width: r*2, height: r*2))
        ctx.clip()

        // 中心发光
        if let g = CGGradient(colorsSpace: cs, colors: [
            UIColor.systemBlue.withAlphaComponent(0.08).cgColor, UIColor.clear.cgColor
        ] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: .init(x:cx,y:cy), startRadius: 0,
                                   endCenter: .init(x:cx,y:cy), endRadius: r*0.5, options: [])
        }

        // ⭐ #9: 扇形渐变（从中心到边缘渐变透明）
        let fan: CGFloat = 90 * .pi / 180
        for i in 0..<40 {
            let frac = CGFloat(i) / 40
            let a1 = rad - fan * (1 - frac)
            let a2 = rad - fan * (1 - frac - 1.0/40)
            let alpha = Double(1 - frac) * 0.18
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(alpha).cgColor)
            ctx.move(to: .init(x: cx, y: cy))
            ctx.addArc(center: .init(x:cx,y:cy), radius: r, startAngle: a1, endAngle: a2, clockwise: false)
            ctx.closePath(); ctx.fillPath()
        }

        // 扫描线（双层发光）
        let end = CGPoint(x: cx + r * 1.05 * cos(rad), y: cy + r * 1.05 * sin(rad))
        // 外层发光
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.2).cgColor)
        ctx.setLineWidth(8); ctx.setLineCap(.round)
        ctx.move(to: .init(x:cx,y:cy)); ctx.addLine(to: end); ctx.strokePath()
        // 内层亮线
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.5)
        ctx.move(to: .init(x:cx,y:cy)); ctx.addLine(to: end); ctx.strokePath()

        // 中心点
        ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.8).cgColor)
        ctx.fillEllipse(in: .init(x: cx-3, y: cy-3, width: 6, height: 6))
        ctx.restoreGState()

        // ⭐ #29: 绘制扫描粒子
        for particle in sweepParticles {
            let lifeRatio = particle.life / particle.maxLife
            let alpha = lifeRatio * 0.7
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(alpha).cgColor)
            let s = CGFloat(particle.size * lifeRatio)
            ctx.fillEllipse(in: CGRect(x: CGFloat(particle.x) - s/2, y: CGFloat(particle.y) - s/2, width: s, height: s))
        }

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

        // 绘制 SF Symbol car.fill（白色，清晰可见）
        let half = carSz / 2
        let carRect = CGRect(x: carX - half, y: carY - half, width: carSz, height: carSz)
        if let carImage = UIImage(systemName: "car.fill") {
            // 白色着色
            let config = UIImage.SymbolConfiguration(pointSize: carSz * 0.7, weight: .medium)
            if let symbolImage = UIImage(systemName: "car.fill", withConfiguration: config) {
                let renderer = UIGraphicsImageRenderer(size: symbolImage.size)
                let tinted = renderer.image { ctx in
                    UIColor.white.withAlphaComponent(0.85).setFill()
                    symbolImage.draw(in: CGRect(origin: .zero, size: symbolImage.size))
                    ctx.fillBlendMode = .sourceAtop
                    UIColor.white.withAlphaComponent(0.85).setFill()
                    ctx.fill(CGRect(origin: .zero, size: symbolImage.size))
                }
                let drawRect = CGRect(
                    x: carX - tinted.size.width / 2,
                    y: carY - tinted.size.height / 2,
                    width: tinted.size.width,
                    height: tinted.size.height
                )
                tinted.draw(in: drawRect)
            }
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

// MARK: - Radar Card (包含雷达 + dBm + 状态胶囊)
struct RadarCardView: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var motion: MotionManager
    @State private var rssiText = "-42 dBm"
    @State private var rssiValue: Double = -42
    private let radar = RadarUIView(frame: .zero)

    // dBm 颜色：强→蓝，弱→红
    private var rssiColor: Color {
        let strength = max(0, min(1, (rssiValue + 110) / 80)) // -110→0, -30→1
        if strength > 0.6 {
            return Color(red: 0.2, green: 0.6, blue: 1.0)    // 强：蓝
        } else if strength > 0.3 {
            return Color(red: 1.0, green: 0.7, blue: 0.2)    // 中：橙
        } else {
            return Color(red: 1.0, green: 0.3, blue: 0.2)    // 弱：红
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // 雷达 + dBm 叠加
            ZStack {
                RadarRepresentable(motion: motion, radar: radar)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())

                // dBm 信号值 — 根据强度变色
                HStack(spacing: 3) {
                    Text(rssiText.replacingOccurrences(of: " dBm", with: ""))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    Text("dBm")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(rssiColor)
            }

            // 状态胶囊
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
