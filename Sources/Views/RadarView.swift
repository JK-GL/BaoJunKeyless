import SwiftUI
import UIKit

// MARK: - 雷达（静态背景图层 + 动态车图层）

struct StarParticle { var x: Double; var y: Double; var size: Double; var alpha: Double }

final class RadarUIView: UIView {
    private let sz: CGFloat = 280
    private var pitch: Double = 0
    private var roll: Double = 0

    var relativeAngle: Double = 0
    var distance: Double = 0
    var bleConnected: Bool = false

    private let backgroundImageView = UIImageView()
    private let glowView = UIView()
    private let carImageView = UIImageView()
    private var memoryWarningObserver: NSObjectProtocol?
    private var stars: [StarParticle] = []
    private var lastCacheSize: CGSize = .zero
    private var displayedCarCenter: CGPoint = .zero
    private var displayedCarSize: CGFloat = 34
    private var carOnlineImage: UIImage?

    private static let carImageURL = URL(string: "https://cdn-df.00bang.cn/images/T1Dw_TBTEv1RCvBVdK.png")!
    private static var sharedCarImage: UIImage?
    private static var sharedCarImageLoadInFlight = false
    private static var staticBackgroundCache: [String: UIImage] = [:]

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

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundImageView.frame = bounds

        if backgroundImageView.image == nil || lastCacheSize != bounds.size {
            rebuildStaticBackground(bounds.size)
        }

        if displayedCarCenter == .zero {
            displayedCarCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        updatePosition(force: true)
    }

    private func setup() {
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false

        stars = (0..<50).map { _ in
            StarParticle(
                x: Double.random(in: 0...1),
                y: Double.random(in: 0...1),
                size: Double.random(in: 0.5...2.0),
                alpha: Double.random(in: 0.03...0.12)
            )
        }

        backgroundImageView.contentMode = .scaleToFill
        backgroundImageView.clipsToBounds = true
        addSubview(backgroundImageView)

        glowView.isUserInteractionEnabled = false
        glowView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        glowView.layer.cornerCurve = .continuous
        glowView.isHidden = !AppDiagnosticsSettings.isRadarGradientEnabled
        addSubview(glowView)

        carImageView.contentMode = .scaleAspectFit
        carImageView.clipsToBounds = false
        addSubview(carImageView)

        if let shared = Self.sharedCarImage {
            carOnlineImage = shared
            carImageView.image = shared
        } else {
            carImageView.image = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            loadCarImage()
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            CrashLogger.shared.mark("Radar", "memoryWarning")
            self?.backgroundImageView.image = nil
            self?.lastCacheSize = .zero
        }
    }

    func updateGyro(pitch: Double, roll: Double) {
        self.pitch = pitch
        self.roll = roll
    }

    func clearTransientCache() {
        backgroundImageView.image = nil
        lastCacheSize = .zero
    }

    func updatePosition(force: Bool = false) {
        guard bounds.width > 0 else { return }

        let cx = bounds.midX
        let cy = bounds.midY
        let r = min(bounds.width, bounds.height) / 2
        let norm = min(distance / 200.0, 1.0)
        let targetRadius = r * 0.15 + CGFloat(norm) * (r * 0.7)
        let angle = relativeAngle * .pi / 180 - .pi / 2
        let targetCenter = CGPoint(
            x: cx + targetRadius * cos(angle),
            y: cy + targetRadius * sin(angle)
        )
        let targetSize = max(sz * (0.28 - 0.15 * CGFloat(norm)), 34)

        let nextCenter: CGPoint
        let nextSize: CGFloat
        if force || displayedCarCenter == .zero {
            nextCenter = targetCenter
            nextSize = targetSize
        } else {
            let dx = targetCenter.x - displayedCarCenter.x
            let dy = targetCenter.y - displayedCarCenter.y
            nextCenter = CGPoint(
                x: displayedCarCenter.x + dx * 0.22,
                y: displayedCarCenter.y + dy * 0.22
            )
            nextSize = displayedCarSize + (targetSize - displayedCarSize) * 0.22
        }

        displayedCarCenter = nextCenter
        displayedCarSize = nextSize

        let glowSize = displayedCarSize * 1.8
        glowView.isHidden = !AppDiagnosticsSettings.isRadarGradientEnabled
        glowView.frame = CGRect(
            x: displayedCarCenter.x - glowSize / 2,
            y: displayedCarCenter.y - glowSize / 2,
            width: glowSize,
            height: glowSize
        )
        glowView.layer.cornerRadius = glowSize / 2
        glowView.alpha = AppDiagnosticsSettings.isRadarGradientEnabled ? 1 : 0

        carImageView.frame = CGRect(
            x: displayedCarCenter.x - displayedCarSize / 2,
            y: displayedCarCenter.y - displayedCarSize / 2,
            width: displayedCarSize,
            height: displayedCarSize
        )
    }

    private func rebuildStaticBackground(_ size: CGSize) {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let cached = Self.staticBackgroundCache[key] {
            backgroundImageView.image = cached
            lastCacheSize = size
            return
        }

        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            CrashLogger.shared.mark("Radar", "rebuildStaticCache", details: key)
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let ctx = context.cgContext
            let cx = size.width / 2
            let cy = size.height / 2
            let r = min(size.width, size.height) / 2
            let tc = UIColor.label

            for deg in 0..<360 {
                let a = CGFloat(deg) * .pi / 180
                let major = deg % 30 == 0
                let mid = deg % 10 == 0
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
                ctx.fillEllipse(in: CGRect(
                    x: CGFloat(s.x) * size.width - s.size / 2,
                    y: CGFloat(s.y) * size.height - s.size / 2,
                    width: s.size,
                    height: s.size
                ))
            }
        }

        Self.staticBackgroundCache[key] = image
        backgroundImageView.image = image
        lastCacheSize = size
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
                    let fallback = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    self?.carOnlineImage = fallback
                    self?.carImageView.image = fallback
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
                self?.carImageView.image = finalImage
                self?.updatePosition(force: true)
            }
        }
        task.resume()
    }
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
        RadarUIView(frame: .zero)
    }

    func updateUIView(_ view: RadarUIView, context: Context) {
        view.updateGyro(pitch: motion.pitch, roll: motion.roll)
        view.relativeAngle = locationManager.relativeAngle
        view.distance = locationManager.distance
        view.bleConnected = bleConnected
        view.updatePosition()
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
