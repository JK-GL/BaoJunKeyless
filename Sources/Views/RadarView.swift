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
    private var pitch: Double = 0
    private var roll: Double = 0
    private var link: CADisplayLink?
    private var lastWaveTime: CFTimeInterval = 0
    var onRssiChange: ((Double) -> Void)?

    private var carSz: CGFloat = 70
    private var carX: CGFloat = 0
    private var carY: CGFloat = 0

    // ⭐ GPS 真实定位
    var relativeAngle: Double = 0    // 车辆相对角度（0=正前方）
    var distance: Double = 0          // 车辆距离（米）
    var bleConnected: Bool = false    // BLE 连接状态

    // 静态缓存
    private var staticCache: UIImage?
    private var lastCacheSize: CGSize = .zero

    // ⭐ dBm 文字缓存
    private var dbmCacheText: String = ""
    private var dbmCacheImage: UIImage?

    // ⭐ 车辆图标缓存
    private var carCacheSize: CGFloat = 0
    private var carCacheImage: UIImage?

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
    deinit { link?.invalidate() }

    // 静态元素缓存（只在尺寸变化时重建一次）
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

        // ⭐ 星空粒子（静态，不闪烁，只画一次）
        for star in stars {
            let sx = CGFloat(star.x) * size.width
            let sy = CGFloat(star.y) * size.height
            ctx.setFillColor(UIColor.white.withAlphaComponent(star.alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: sx - star.size/2, y: sy - star.size/2, width: star.size, height: star.size))
        }

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        staticCache = result
        lastCacheSize = size
    }

    // ⭐ 缓存 dBm 文字图片
    private func buildDbmCache() {
        let text = String(format: "%.0f", rssi)
        guard text != dbmCacheText else { return }
        dbmCacheText = text

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0.9)
        ]
        let unitAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.45)
        ]
        let full = NSMutableAttributedString()
        full.append(NSAttributedString(string: text, attributes: attrs))
        full.append(NSAttributedString(string: " dBm", attributes: unitAttrs))
        let size = full.size()

        let renderer = UIGraphicsImageRenderer(size: size)
        dbmCacheImage = renderer.image { ctx in
            full.draw(at: .zero)
        }
    }

    // ⭐ 缓存车辆图标图片
    private func buildCarCache() {
        guard abs(carSz - carCacheSize) > 1.0 else { return }
        carCacheSize = carSz
        let config = UIImage.SymbolConfiguration(pointSize: carSz * 0.6, weight: .medium)
        carCacheImage = UIImage(systemName: "car.fill", withConfiguration: config)?
            .withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
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

        // ⭐ 绘制渐变波纹
        for wave in waves {
            let progress = wave.life  // 0→1
            let waveR = wave.maxRadius * CGFloat(progress)
            let alpha = CGFloat(pow(1 - progress, 1.5)) * 0.7  // 非线性衰减

            // 波纹光晕（简化为 3 色渐变）
            let outerR = waveR + 10
            let innerR = max(waveR - 6, 0)
            if outerR > 0, let g = CGGradient(colorsSpace: cs, colors: [
                UIColor.clear.cgColor,
                UIColor.systemBlue.withAlphaComponent(Double(alpha * 0.6)).cgColor,
                UIColor.clear.cgColor
            ] as CFArray, locations: [0, 0.5, 1]) {
                ctx.drawRadialGradient(g,
                    startCenter: .init(x: cx, y: cy), startRadius: innerR,
                    endCenter: .init(x: cx, y: cy), endRadius: outerR,
                    options: [])
            }

            // 内层亮环
            ctx.setStrokeColor(UIColor(red: 0.5, green: 0.85, blue: 1.0, alpha: Double(alpha * 0.7)).cgColor)
            ctx.setLineWidth(max(1.0 * (1 - progress), 0.3))
            ctx.strokeEllipse(in: .init(
                x: cx - waveR, y: cy - waveR,
                width: waveR * 2, height: waveR * 2
            ))
        }

        ctx.restoreGState()

        // ── 信号文字（BLE 连接显示 dBm，未连接显示 GPS）──
        if bleConnected {
            // dBm 文字（缓存绘制）
            buildDbmCache()
            if let img = dbmCacheImage {
                img.draw(at: CGPoint(x: cx - img.size.width/2, y: cy - img.size.height/2))
            }
        } else {
            // GPS 标识小胶囊
            let gpsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.systemGreen.withAlphaComponent(0.9)
            ]
            let gpsText = NSAttributedString(string: "GPS", attributes: gpsAttrs)
            let textSize = gpsText.size()
            let capsuleW = textSize.width + 16
            let capsuleH = textSize.height + 8
            let capsuleRect = CGRect(x: cx - capsuleW/2, y: cy - capsuleH/2, width: capsuleW, height: capsuleH)

            // 胶囊底板
            let capsulePath = UIBezierPath(roundedRect: capsuleRect, cornerRadius: capsuleH / 2)
            UIColor.systemGreen.withAlphaComponent(0.12).setFill()
            capsulePath.fill()
            UIColor.systemGreen.withAlphaComponent(0.25).setStroke()
            capsulePath.lineWidth = 0.5
            capsulePath.stroke()

            // 文字
            gpsText.draw(at: CGPoint(x: cx - textSize.width/2, y: cy - textSize.height/2))
        }

        // ── 车辆图标（GPS 真实定位）──
        // relativeAngle: 0=正上方(12点), 90=右(3点), 180=下(6点), 270=左(9点)
        // distance: 车辆距离（米），映射到雷达半径（最大显示 200 米）
        let maxDisplayDistance: Double = 200.0
        let normalizedDist = min(distance / maxDisplayDistance, 1.0)  // 0~1
        let carRadius = r * 0.15 + CGFloat(normalizedDist) * (r * 0.7)  // 最小 15% 半径
        let angleRad = relativeAngle * .pi / 180 - .pi / 2  // 0°→上，顺时针
        let targetX = cx + carRadius * cos(angleRad)
        let targetY = cy + carRadius * sin(angleRad)
        carX += (targetX - carX) * 0.08
        carY += (targetY - carY) * 0.08

        // 车辆大小随距离变化：近→大，远→小
        let tSz: CGFloat = sz * (0.28 - 0.15 * CGFloat(normalizedDist))
        carSz += (tSz - carSz) * 0.05

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

        // 车辆图标（缓存）
        buildCarCache()
        if let img = carCacheImage {
            img.draw(in: CGRect(x: carX - img.size.width/2, y: carY - img.size.height/2,
                                width: img.size.width, height: img.size.height))
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }
}

// MARK: - SwiftUI 封装
struct RadarRepresentable: UIViewRepresentable {
    @ObservedObject var motion: MotionManager
    @ObservedObject var locationManager: LocationManager
    let radar: RadarUIView
    var bleConnected: Bool = false
    func makeUIView(context: Context) -> RadarUIView { radar }
    func updateUIView(_ v: RadarUIView, context: Context) {
        v.updateGyro(pitch: motion.pitch, roll: motion.roll)
        v.relativeAngle = locationManager.relativeAngle
        v.distance = locationManager.distance
        v.bleConnected = bleConnected
    }
}

// MARK: - Radar Card
struct RadarCardView: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var motion: MotionManager
    @ObservedObject var locationManager: LocationManager
    @State private var rssiText = "-42"
    @State private var rssiValue: Double = -42
    @State private var displayValue: Double = -42
    @State private var bleConnected = false  // ⭐ BLE 连接状态（模拟未连接）
    private let radar = RadarUIView(frame: .zero)

    // 车辆 GPS 坐标（从 MQTT 获取）
    private let carLat = 22.635842
    private let carLng = 114.129604

    private var strength: Double {
        max(0, min(1, (rssiValue + 110) / 80))
    }

    private var gradientColors: [Color] {
        if strength > 0.6 {
            return [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.3, green: 0.9, blue: 1.0)]
        } else if strength > 0.3 {
            return [Color(red: 1.0, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.5, blue: 0.3)]
        } else {
            return [Color(red: 1.0, green: 0.3, blue: 0.2), Color(red: 1.0, green: 0.5, blue: 0.3)]
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // 雷达（dBm 在 Canvas 内部绘制）
            RadarRepresentable(motion: motion, locationManager: locationManager, radar: radar, bleConnected: bleConnected)
                .frame(width: 280, height: 280)
                .clipShape(Circle())

            // 距离显示
            if locationManager.distance > 0 {
                Text(String(format: "距车辆 %.0f 米", locationManager.distance))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
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
            // 设置车辆坐标
            locationManager.setCarLocation(lat: carLat, lng: carLng)

            radar.onRssiChange = { val in
                DispatchQueue.main.async {
                    rssiValue = val
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        displayValue = val
                    }
                }
            }
        }
        .onChange(of: locationManager.relativeAngle) { val in
            radar.relativeAngle = val
        }
        .onChange(of: locationManager.distance) { val in
            radar.distance = val
        }
    }
}
