import SwiftUI
import UIKit

// MARK: - 声波涟漪雷达（Core Graphics 静态 + SwiftUI 波纹动画）

// MARK: - 星空粒子
struct StarParticle {
    var x: Double
    var y: Double
    var size: Double
    var alpha: Double
}

// MARK: - 雷达 UIView（只画静态元素 + 车辆图标）
class RadarUIView: UIView {
    private let sz: CGFloat = 280
    private var rssi: Double = -42
    private var pitch: Double = 0
    private var roll: Double = 0
    var onRssiChange: ((Double) -> Void)?

    private var carSz: CGFloat = 70
    private var carX: CGFloat = 0
    private var carY: CGFloat = 0

    var relativeAngle: Double = 0
    var distance: Double = 0
    var bleConnected: Bool = false

    private var staticCache: UIImage?
    private var lastCacheSize: CGSize = .zero
    private var dbmCacheText: String = ""
    private var dbmCacheImage: UIImage?
    private var carCacheSize: CGFloat = 0
    private var carCacheImage: UIImage?
    private var carOnlineImage: UIImage?
    private var stars: [StarParticle] = []

    private let carImageURL = "https://cdn-df.00bang.cn/images/T1Dw_TBTEv1RCvBVdK.png"

    // 定时更新车辆位置（不需要每帧刷新）
    private var updateTimer: Timer?

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        isOpaque = false; backgroundColor = .clear
        generateStars()
        loadCarImage()
        // 每 0.1 秒更新一次车辆位置（足够流畅，不卡）
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCarPosition()
            self?.setNeedsDisplay()
        }
    }

    private func loadCarImage() {
        guard let url = URL(string: carImageURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.carOnlineImage = img }
        }.resume()
    }

    private func generateStars() {
        stars = (0..<50).map { _ in
            StarParticle(
                x: Double.random(in: 0...1), y: Double.random(in: 0...1),
                size: Double.random(in: 0.5...2.0), alpha: Double.random(in: 0.03...0.12)
            )
        }
    }

    private func updateCarPosition() {
        guard bounds.width > 0 else { return }
        let cx = bounds.midX, cy = bounds.midY, r = sz / 2
        let maxDist: Double = 200.0
        let norm = min(distance / maxDist, 1.0)
        let carR = r * 0.15 + CGFloat(norm) * (r * 0.7)
        let angle = relativeAngle * .pi / 180 - .pi / 2
        let tx = cx + carR * cos(angle)
        let ty = cy + carR * sin(angle)
        carX += (tx - carX) * 0.08
        carY += (ty - carY) * 0.08
        let tSz = sz * (0.28 - 0.15 * CGFloat(norm))
        carSz += (tSz - carSz) * 0.05
    }

    deinit { updateTimer?.invalidate() }

    // 静态元素缓存
    private func buildStaticCache(_ size: CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = size.width / 2, cy = size.height / 2, r = sz / 2
        let tickColor = UIColor.label

        for deg in 0..<360 {
            let a = CGFloat(deg) * .pi / 180
            let major = deg % 30 == 0, mid = deg % 10 == 0
            let inner: CGFloat = major ? r - 18 : (mid ? r - 11 : r - 7)
            let alpha: Double = major ? 0.45 : (mid ? 0.2 : 0.08)
            let w: CGFloat = major ? 1.5 : (mid ? 0.8 : 0.3)
            ctx.setStrokeColor(tickColor.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(w)
            ctx.move(to: .init(x: cx + inner * cos(a), y: cy + inner * sin(a)))
            ctx.addLine(to: .init(x: cx + (r - 1) * cos(a), y: cy + (r - 1) * sin(a)))
            ctx.strokePath()
        }

        ctx.setStrokeColor(tickColor.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: .init(x: cx-r+1, y: cy-r+1, width: (r-1)*2, height: (r-1)*2))

        for i in 1...3 {
            let rr = r * CGFloat(i) / 3.5
            ctx.setStrokeColor(tickColor.withAlphaComponent(0.04 + Double(i)*0.02).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: .init(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2))
        }

        ctx.setStrokeColor(tickColor.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: .init(x:cx,y:cy-r+14)); ctx.addLine(to: .init(x:cx,y:cy+r-14))
        ctx.move(to: .init(x:cx-r+14,y:cy)); ctx.addLine(to: .init(x:cx+r-14,y:cy))
        ctx.strokePath()

        for star in stars {
            let sx = CGFloat(star.x) * size.width, sy = CGFloat(star.y) * size.height
            ctx.setFillColor(UIColor.white.withAlphaComponent(star.alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: sx-star.size/2, y: sy-star.size/2, width: star.size, height: star.size))
        }

        staticCache = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        lastCacheSize = size
    }

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
        let sz = full.size()
        dbmCacheImage = UIGraphicsImageRenderer(size: sz).image { _ in full.draw(at: .zero) }
    }

    private func buildCarCache() {
        guard abs(carSz - carCacheSize) > 1.0 else { return }
        carCacheSize = carSz
        if let online = carOnlineImage {
            let maxSide = carSz * 0.8
            let scale = min(maxSide / online.size.width, maxSide / online.size.height)
            let w = online.size.width * scale, h = online.size.height * scale
            carCacheImage = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
                online.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: carSz * 0.6, weight: .medium)
            carCacheImage = UIImage(systemName: "car.fill", withConfiguration: cfg)?
                .withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = rect.midX, cy = rect.midY, r = sz / 2

        if staticCache == nil || lastCacheSize != bounds.size { buildStaticCache(bounds.size) }
        staticCache?.draw(at: .zero)

        // GPS / dBm 文字
        if bleConnected {
            buildDbmCache()
            dbmCacheImage?.draw(at: CGPoint(x: cx - (dbmCacheImage?.size.width ?? 0)/2, y: cy - (dbmCacheImage?.size.height ?? 0)/2))
        } else {
            let gpsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.systemGreen.withAlphaComponent(0.9)
            ]
            let gpsText = NSAttributedString(string: "GPS", attributes: gpsAttrs)
            let ts = gpsText.size()
            let rect = CGRect(x: cx - (ts.width+16)/2, y: cy - (ts.height+8)/2, width: ts.width+16, height: ts.height+8)
            UIBezierPath(roundedRect: rect, cornerRadius: rect.height/2).fill()
            UIColor.systemGreen.withAlphaComponent(0.12).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: rect.height/2).fill()
            UIColor.systemGreen.withAlphaComponent(0.25).setStroke()
            UIBezierPath(roundedRect: rect, cornerRadius: rect.height/2).lineWidth = 0.5
            UIBezierPath(roundedRect: rect, cornerRadius: rect.height/2).stroke()
            gpsText.draw(at: CGPoint(x: cx - ts.width/2, y: cy - ts.height/2))
        }

        // 车辆图标
        let cs = CGColorSpaceCreateDeviceRGB()
        let glowR = carSz * 0.7
        if let g = CGGradient(colorsSpace: cs, colors: [
            UIColor.systemBlue.withAlphaComponent(0.12).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.04).cgColor,
            UIColor.clear.cgColor
        ] as CFArray, locations: [0, 0.5, 1]) {
            ctx.drawRadialGradient(g, startCenter: .init(x:carX,y:carY), startRadius: 0,
                                   endCenter: .init(x:carX,y:carY), endRadius: glowR, options: [])
        }
        buildCarCache()
        carCacheImage?.draw(in: CGRect(x: carX - (carCacheImage?.size.width ?? 0)/2,
                                        y: carY - (carCacheImage?.size.height ?? 0)/2,
                                        width: carCacheImage?.size.width ?? 0,
                                        height: carCacheImage?.size.height ?? 0))
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }
}

// MARK: - SwiftUI 波纹动画（替代 Core Graphics 波纹）
struct WaveRippleView: View {
    @State private var waveID = 0
    let radarSize: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                WaveCircle(index: i, radarSize: radarSize)
            }
        }
        .frame(width: radarSize, height: radarSize)
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

struct WaveCircle: View {
    let index: Int
    let radarSize: CGFloat
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0),
                        Color.blue.opacity(0.35),
                        Color.blue.opacity(0)
                    ],
                    startPoint: .center,
                    endPoint: .center
                ),
                lineWidth: 1.5
            )
            .frame(width: radarSize * 0.3, height: radarSize * 0.3)
            .scaleEffect(animate ? 1.0 : 0.1)
            .opacity(animate ? 0.0 : 0.7)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.2) {
                    withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
            }
    }
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
    @State private var rssiValue: Double = -42
    @State private var displayValue: Double = -42
    @State private var bleConnected = false
    private let radar = RadarUIView(frame: .zero)

    private let carLat = 22.635842
    private let carLng = 114.129604

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // 静态雷达 + 车辆图标
                RadarRepresentable(motion: motion, locationManager: locationManager, radar: radar, bleConnected: bleConnected)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())

                // ⭐ SwiftUI 波纹动画（叠加在雷达上）
                WaveRippleView(radarSize: 280)
            }

            if locationManager.distance > 0 {
                Text(String(format: "距车辆 %.0f 米", locationManager.distance))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .onAppear {
            locationManager.setCarLocation(lat: carLat, lng: carLng)
        }
        .onChange(of: locationManager.relativeAngle) { val in radar.relativeAngle = val }
        .onChange(of: locationManager.distance) { val in radar.distance = val }
    }
}
