import SwiftUI
import UIKit

// MARK: - 雷达（Core Graphics 静态 + SwiftUI 文字/波纹）

struct StarParticle { var x: Double; var y: Double; var size: Double; var alpha: Double }

// MARK: - 雷达 UIView（只画刻度 + 车辆图标，文字全部交给 SwiftUI）
final class RadarUIView: UIView {
    private let sz: CGFloat = 280
    private var pitch: Double = 0
    private var roll: Double = 0

    var relativeAngle: Double = 0
    var distance: Double = 0
    var bleConnected: Bool = false

    private var staticCache: UIImage?
    private var lastCacheSize: CGSize = .zero
    private var carCacheTargetSize: CGFloat = 34
    private var cachedRenderedCarSize: CGFloat = 0
    private var carCacheImage: UIImage?
    private var carOnlineImage: UIImage?
    private var memoryWarningObserver: NSObjectProtocol?
    private var stars: [StarParticle] = []
    private var carX: CGFloat = 0
    private var carY: CGFloat = 0
    private var drawCount = 0
    private var lastDrawLogCount = 0

    private static let carImageURL = URL(string: "https://cdn-df.00bang.cn/images/T1Dw_TBTEv1RCvBVdK.png")!
    private static var sharedCarImage: UIImage?
    private static var sharedCarImageLoadInFlight = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            CrashLogger.shared.mark("Radar", "init")
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            CrashLogger.shared.mark("Radar", "init(coder)")
        }
    }

    deinit {
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            CrashLogger.shared.mark("Radar", "deinit")
        }
    }

    private func setup() {
        isOpaque = false
        backgroundColor = .clear
        stars = (0..<50).map { _ in
            StarParticle(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 0.5...2.0),
                alpha: Double.random(in: 0.03...0.12)
            )
        }
        if let shared = Self.sharedCarImage {
            carOnlineImage = shared
        } else {
            loadCarImage()
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            CrashLogger.shared.mark("Radar", "memoryWarning")
            self?.staticCache = nil
            self?.carCacheImage = nil
        }
    }

    // ⭐ 由 SwiftUI onChange 调用，自动适配设备刷新率
    func updatePosition() {
        guard bounds.width > 0 else { return }
        let cx = bounds.midX, cy = bounds.midY, r = sz / 2
        let norm = min(distance / 200.0, 1.0)
        let carR = r * 0.15 + CGFloat(norm) * (r * 0.7)
        let angle = relativeAngle * .pi / 180 - .pi / 2
        let tx = cx + carR * cos(angle)
        let ty = cy + carR * sin(angle)
        let dx = tx - carX
        let dy = ty - carY
        let movement = max(abs(dx), abs(dy))
        if movement > 1.2 {
            carX += dx * 0.18
            carY += dy * 0.18
            let targetSize = sz * (0.28 - 0.15 * CGFloat(norm))
            carCacheTargetSize = max(targetSize, 34)
            setNeedsDisplay()
        }
    }

    func updateGyro(pitch: Double, roll: Double) {
        self.pitch = pitch
        self.roll = roll
    }

    func clearTransientCache() {
        staticCache = nil
        carCacheImage = nil
    }

    private func loadCarImage() {
        CrashLogger.shared.mark("Radar", "loadCarImage:start")
        if Self.sharedCarImageLoadInFlight { return }
        Self.sharedCarImageLoadInFlight = true

        let request = URLRequest(url: Self.carImageURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { Self.sharedCarImageLoadInFlight = false }
            guard let data = data, let img = UIImage(data: data) else {
                DispatchQueue.main.async { [weak self] in
                    self?.carOnlineImage = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                }
                return
            }

            let finalImage = img
            Self.sharedCarImage = finalImage
            if AppDiagnosticsSettings.isDiagnosticsEnabled {
                CrashLogger.shared.logImageDiagnostics(
                    "RadarCar",
                    width: finalImage.size.width,
                    height: finalImage.size.height,
                    bytes: data.count,
                    note: "network"
                )
            }
            DispatchQueue.main.async { [weak self] in
                self?.carOnlineImage = finalImage
                self?.carCacheImage = nil
                self?.setNeedsDisplay()
            }
        }
        task.resume()
    }

    private func buildStaticCache(_ size: CGSize) {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let cx = size.width / 2, cy = size.height / 2, r = sz / 2
            let tc = UIColor.label

            for deg in 0..<360 {
                let a = CGFloat(deg) * .pi / 180
                let major = deg % 30 == 0, mid = deg % 10 == 0
                let inner: CGFloat = major ? r - 18 : (mid ? r - 11 : r - 7)
                ctx.setStrokeColor(tc.withAlphaComponent(major ? 0.45 : (mid ? 0.2 : 0.08)).cgColor)
                ctx.setLineWidth(major ? 1.5 : (mid ? 0.8 : 0.3))
                ctx.move(to: .init(x: cx + inner * cos(a), y: cy + inner * sin(a)))
                ctx.addLine(to: .init(x: cx + (r - 1) * cos(a), y: cy + (r - 1) * sin(a)))
                ctx.strokePath()
            }
            ctx.setStrokeColor(tc.withAlphaComponent(0.15).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: .init(x: cx - r + 1, y: cy - r + 1, width: (r - 1) * 2, height: (r - 1) * 2))

            for i in 1...3 {
                let rr = r * CGFloat(i) / 3.5
                ctx.setStrokeColor(tc.withAlphaComponent(0.04 + Double(i) * 0.02).cgColor)
                ctx.setLineWidth(0.5)
                ctx.strokeEllipse(in: .init(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
            }

            ctx.setStrokeColor(tc.withAlphaComponent(0.06).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: .init(x: cx, y: cy - r + 14))
            ctx.addLine(to: .init(x: cx, y: cy + r - 14))
            ctx.move(to: .init(x: cx - r + 14, y: cy))
            ctx.addLine(to: .init(x: cx + r - 14, y: cy))
            ctx.strokePath()

            for s in stars {
                ctx.setFillColor(UIColor.white.withAlphaComponent(s.alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: CGFloat(s.x) * size.width - s.size / 2,
                                           y: CGFloat(s.y) * size.height - s.size / 2,
                                           width: s.size,
                                           height: s.size))
            }
        }

        staticCache = image
        lastCacheSize = size
    }

    private func buildCarCache() {
        let targetSize = max(carCacheTargetSize, 34)
        guard abs(targetSize - cachedRenderedCarSize) > 2.0 || carCacheImage == nil else { return }
        cachedRenderedCarSize = targetSize

        if let img = carOnlineImage {
            let ms = targetSize * 0.8
            let sc = min(ms / max(img.size.width, 1), ms / max(img.size.height, 1))
            let w = max(img.size.width * sc, 1)
            let h = max(img.size.height * sc, 1)
            carCacheImage = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
                img.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        } else {
            carCacheImage = UIImage(
                systemName: "car.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: targetSize * 0.6, weight: .medium)
            )?.withTintColor(UIColor.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        drawCount += 1
        if AppDiagnosticsSettings.isDiagnosticsEnabled, drawCount - lastDrawLogCount >= 120 {
            lastDrawLogCount = drawCount
            CrashLogger.shared.mark("Radar", "drawCount", details: "count=\(drawCount)")
        }

        if staticCache == nil || lastCacheSize != bounds.size {
            CrashLogger.shared.mark("Radar", "rebuildStaticCache", details: "\(Int(bounds.size.width))x\(Int(bounds.size.height))")
            buildStaticCache(bounds.size)
        }
        staticCache?.draw(at: .zero)

        if AppDiagnosticsSettings.isRadarGradientEnabled {
            let cs = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: cs,
                                  colors: [UIColor.systemBlue.withAlphaComponent(0.12).cgColor,
                                           UIColor.systemBlue.withAlphaComponent(0.04).cgColor,
                                           UIColor.clear.cgColor] as CFArray,
                                  locations: [0, 0.5, 1]) {
                ctx.drawRadialGradient(g,
                                       startCenter: .init(x: carX, y: carY),
                                       startRadius: 0,
                                       endCenter: .init(x: carX, y: carY),
                                       endRadius: cachedRenderedCarSize * 0.7,
                                       options: [])
            }
        }

        buildCarCache()
        if let img = carCacheImage {
            img.draw(in: CGRect(x: carX - img.size.width / 2,
                                y: carY - img.size.height / 2,
                                width: img.size.width,
                                height: img.size.height))
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }
}

// MARK: - SwiftUI 波纹动画
struct PsychicScanView: View {
    let size: CGFloat
    @AppStorage(AppDiagnosticsSettings.enableRadarScanKey) private var enableRadarScan = false

    var body: some View {
        if enableRadarScan {
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    ScanRing(index: i, size: size)
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
        }
    }
}

struct ScanRing: View {
    let index: Int
    let size: CGFloat
    @State private var expand = false

    var body: some View {
        Circle()
            .stroke(Color.cyan.opacity(0.24), lineWidth: 1.0)
            .frame(width: 24, height: 24)
            .scaleEffect(expand ? 9.0 : 0.2)
            .opacity(expand ? 0.0 : 0.45)
            .blur(radius: 0.5)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 1.8) {
                    withAnimation(.easeOut(duration: 3.6).repeatForever(autoreverses: false)) {
                        expand = true
                    }
                }
            }
    }
}

// MARK: - SwiftUI 封装
struct RadarRepresentable: UIViewRepresentable {
    @ObservedObject var motion: MotionManager
    @ObservedObject var locationManager: LocationManager
    var bleConnected: Bool = false

    func makeUIView(context: Context) -> RadarUIView {
        let v = RadarUIView(frame: .zero)
        context.coordinator.radarView = v
        return v
    }

    func updateUIView(_ v: RadarUIView, context: Context) {
        v.updateGyro(pitch: motion.pitch, roll: motion.roll)
        v.relativeAngle = locationManager.relativeAngle
        v.distance = locationManager.distance
        v.bleConnected = bleConnected
        v.updatePosition()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var radarView: RadarUIView?
    }
}

// MARK: - Radar Card（文字全部用 SwiftUI Text）
struct RadarCardView: View {
    @EnvironmentObject var theme: ThemeManager
    @ObservedObject var motion: MotionManager
    @ObservedObject var locationManager: LocationManager
    @State private var bleConnected = false
    private let carLat = 22.635842
    private let carLng = 114.129604

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RadarRepresentable(motion: motion, locationManager: locationManager, bleConnected: bleConnected)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())

                PsychicScanView(size: 280)

                if bleConnected {
                    Text("-42 dBm")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(red: 0.2, green: 0.6, blue: 1),
                                                    Color(red: 0.3, green: 0.9, blue: 1)],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                } else {
                    Text("GPS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.green.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.12))
                                .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 0.5))
                        )
                }
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
        .onAppear { locationManager.setCarLocation(lat: carLat, lng: carLng) }
        .onChange(of: locationManager.relativeAngle) { _ in }
        .onChange(of: locationManager.distance) { _ in }
    }
}
