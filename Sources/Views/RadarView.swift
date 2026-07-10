import SwiftUI
import UIKit
import QuartzCore

// MARK: - 雷达（静态背景图层 + 动态车标图层）

struct StarParticle { var x: Double; var y: Double; var size: Double; var alpha: Double }

final class RadarUIView: UIView {
    private let sz: CGFloat = 280

    var relativeAngle: Double = 0
    var distance: Double = 0

    private let backgroundImageView = UIImageView()
    private let carImageView = UIImageView()
    private let scanRing1 = CAShapeLayer()
    private let scanRing2 = CAShapeLayer()
    private var memoryWarningObserver: NSObjectProtocol?
    private var stars: [StarParticle] = []
    private var displayedCarCenter: CGPoint = .zero
    private var displayedCarSize: CGFloat = 34
    private var targetCarCenter: CGPoint = .zero
    private var targetCarSize: CGFloat = 34
    private var markerDisplayLink: CADisplayLink?
    private var lastDisplayLinkTimestamp: CFTimeInterval = 0
    private var lastBackgroundSize: CGSize = .zero
    private var carOnlineImage: UIImage?
    private var isUsingSFSymbolCar = false
    var carImageURLString: String = "" {
        didSet {
            guard oldValue != carImageURLString else { return }
            currentCarImageCacheKey = ""
            if window != nil {
                restoreDynamicResourcesIfNeeded()
                updateMarker(force: true)
            }
        }
    }
    private var currentCarImageCacheKey: String = ""

    private static let defaultCarImageURLString = "https://cdn-df.00bang.cn/images/T1Dw_TBTEv1RCvBVdK.png"
    private static var sharedCarImages: [String: UIImage] = [:]
    private static var sharedCarImageLoadInFlight = Set<String>()
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
        markerDisplayLink?.invalidate()
        markerDisplayLink = nil
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            CrashLogger.shared.mark("Radar", "deinit")
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopMarkerDisplayLink()
            releaseHeavyResources()
        } else {
            // 重新入屏时强制恢复圆圈背景 + 扫描环 + 车图
            restoreDynamicResourcesIfNeeded()
            resumeScanRingAnimationsIfNeeded()
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        layer.masksToBounds = true
        backgroundImageView.frame = bounds
        layoutScanRing(scanRing1)
        layoutScanRing(scanRing2)

        if backgroundImageView.image == nil || lastBackgroundSize != bounds.size {
            rebuildStaticBackground(bounds.size)
        }

        if displayedCarCenter == .zero {
            displayedCarCenter = CGPoint(x: bounds.midX, y: bounds.midY)
            targetCarCenter = displayedCarCenter
        }
        updateMarker(force: true)
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

        backgroundImageView.contentMode = .scaleToFill
        backgroundImageView.isUserInteractionEnabled = false
        addSubview(backgroundImageView)

        configureScanRing(scanRing1, delay: 0)
        configureScanRing(scanRing2, delay: 1.8)

        carImageView.contentMode = .scaleAspectFit
        carImageView.isUserInteractionEnabled = false
        addSubview(carImageView)

        restoreDynamicResourcesIfNeeded()

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            CrashLogger.shared.mark("Radar", "memoryWarning")
            Self.staticBackgroundCache.removeAll()
            guard let self else { return }
            // 仍在屏幕上时不要只清不建，否则会出现“只有车图没有圆圈”
            if self.window != nil {
                self.rebuildStaticBackground(self.bounds.size)
                self.resumeScanRingAnimationsIfNeeded()
            } else {
                self.releaseHeavyResources()
            }
        }
    }

    private func configureScanRing(_ ring: CAShapeLayer, delay: Double) {
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.cyan.withAlphaComponent(0.24).cgColor
        ring.lineWidth = 1.0
        ring.opacity = 0.45
        layer.addSublayer(ring)
        startScanRingAnimation(ring, delay: delay)
    }

    private func startScanRingAnimation(_ ring: CAShapeLayer, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak ring] in
            guard let ring else { return }

            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.2
            scaleAnim.toValue = 9.0
            scaleAnim.duration = 3.6
            scaleAnim.repeatCount = .infinity
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let opacityAnim = CABasicAnimation(keyPath: "opacity")
            opacityAnim.fromValue = 0.45
            opacityAnim.toValue = 0.0
            opacityAnim.duration = 3.6
            opacityAnim.repeatCount = .infinity
            opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let group = CAAnimationGroup()
            group.animations = [scaleAnim, opacityAnim]
            group.duration = 3.6
            group.repeatCount = .infinity

            ring.add(group, forKey: "scanPulse")
        }
    }

    private func resumeScanRingAnimationsIfNeeded() {
        if scanRing1.animation(forKey: "scanPulse") == nil {
            startScanRingAnimation(scanRing1, delay: 0)
        }
        if scanRing2.animation(forKey: "scanPulse") == nil {
            startScanRingAnimation(scanRing2, delay: 1.8)
        }
    }

    private func layoutScanRing(_ ring: CAShapeLayer) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.frame = CGRect(origin: center, size: .zero)
        ring.path = UIBezierPath(ovalIn: CGRect(x: -12, y: -12, width: 24, height: 24)).cgPath
        ring.cornerRadius = 12
    }

    func updateGyro(pitch: Double, roll: Double) {
        // 当前雷达样式中未直接使用陀螺仪角，但保留接口以兼容上层调用。
    }

    func updatePosition(force: Bool = false) {
        restoreDynamicResourcesIfNeeded()
        updateMarker(force: force)
    }

    func clearTransientCache() {
        releaseHeavyResources()
    }

    func releaseHeavyResources() {
        backgroundImageView.image = nil
        scanRing1.removeAllAnimations()
        scanRing2.removeAllAnimations()
        carImageView.layer.removeAllAnimations()
        lastBackgroundSize = .zero
        lastDisplayLinkTimestamp = 0
    }

    private func restoreDynamicResourcesIfNeeded() {
        // 圆圈/刻度背景与车图要一起恢复；之前只恢复了车图，会出现“只有车、没有圈线”
        if bounds.width > 1, bounds.height > 1 {
            if backgroundImageView.image == nil || lastBackgroundSize != bounds.size {
                rebuildStaticBackground(bounds.size)
            }
        } else {
            setNeedsLayout()
        }

        resumeScanRingAnimationsIfNeeded()
        let key = normalizedCarImageCacheKey
        if let shared = Self.sharedCarImages[key] {
            isUsingSFSymbolCar = false
            carOnlineImage = shared
            currentCarImageCacheKey = key
            if carImageView.image !== shared {
                carImageView.image = shared
            }
        } else if carImageView.image == nil || currentCarImageCacheKey != key {
            isUsingSFSymbolCar = false
            currentCarImageCacheKey = key
            carImageView.image = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            loadCarImage()
        }
    }

    private var normalizedCarImageCacheKey: String {
        let trimmed = carImageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultCarImageURLString : trimmed
    }

    private func updateMarker(force: Bool) {
        guard bounds.width > 0 else { return }

        let cx = bounds.midX
        let cy = bounds.midY
        let r = min(bounds.width, bounds.height) / 2
        let norm = min(distance / 200.0, 1.0)
        let targetRadius = r * 0.15 + CGFloat(norm) * (r * 0.7)
        let angle = relativeAngle * .pi / 180 - .pi / 2
        let nextCenter = CGPoint(
            x: cx + targetRadius * CGFloat(cos(angle)),
            y: cy + targetRadius * CGFloat(sin(angle))
        )
        let nextSize = max(sz * (0.28 - 0.15 * CGFloat(norm)), 34)

        let targetChanged = force
            || abs(nextCenter.x - targetCarCenter.x) >= 0.05
            || abs(nextCenter.y - targetCarCenter.y) >= 0.05
            || abs(nextSize - targetCarSize) >= 0.05

        targetCarCenter = nextCenter
        targetCarSize = nextSize

        if force || displayedCarCenter == .zero {
            displayedCarCenter = nextCenter
            displayedCarSize = nextSize
            applyMarkerFrame()
        }

        if targetChanged && !force {
            startMarkerDisplayLinkIfNeeded()
        }
    }

    private func startMarkerDisplayLinkIfNeeded() {
        guard window != nil, markerDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(stepMarkerSmoothing(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        displayLink.add(to: .main, forMode: .common)
        markerDisplayLink = displayLink
    }

    private func stopMarkerDisplayLink() {
        markerDisplayLink?.invalidate()
        markerDisplayLink = nil
        lastDisplayLinkTimestamp = 0
    }

    @objc private func stepMarkerSmoothing(_ displayLink: CADisplayLink) {
        guard window != nil, bounds.width > 0 else {
            stopMarkerDisplayLink()
            return
        }

        if displayedCarCenter == .zero {
            displayedCarCenter = targetCarCenter == .zero ? CGPoint(x: bounds.midX, y: bounds.midY) : targetCarCenter
            displayedCarSize = targetCarSize
            applyMarkerFrame()
            return
        }

        let dt: CGFloat
        if lastDisplayLinkTimestamp == 0 {
            dt = CGFloat(displayLink.targetTimestamp - displayLink.timestamp)
        } else {
            dt = CGFloat(displayLink.timestamp - lastDisplayLinkTimestamp)
        }
        lastDisplayLinkTimestamp = displayLink.timestamp

        // 无弹性平滑追踪：只做指数缓动，不带速度、不允许过冲。
        // 高频传感器只刷新目标点；屏幕每帧向目标点贴近，避免“弹来弹去”的观感。
        let clampedDt = min(max(dt, 1.0 / 120.0), 1.0 / 30.0)
        let positionResponse: CGFloat = 22.0
        let sizeResponse: CGFloat = 18.0
        let positionAlpha = min(max(1 - exp(-positionResponse * clampedDt), 0.20), 0.48)
        let sizeAlpha = min(max(1 - exp(-sizeResponse * clampedDt), 0.16), 0.38)

        let dx = targetCarCenter.x - displayedCarCenter.x
        let dy = targetCarCenter.y - displayedCarCenter.y
        let ds = targetCarSize - displayedCarSize

        displayedCarCenter = CGPoint(
            x: displayedCarCenter.x + dx * positionAlpha,
            y: displayedCarCenter.y + dy * positionAlpha
        )
        displayedCarSize += ds * sizeAlpha

        if abs(dx) < 0.18, abs(dy) < 0.18, abs(ds) < 0.10 {
            displayedCarCenter = targetCarCenter
            displayedCarSize = targetCarSize
            applyMarkerFrame()
            stopMarkerDisplayLink()
            return
        }

        applyMarkerFrame()
    }

    private func applyMarkerFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        carImageView.bounds = CGRect(x: 0, y: 0, width: displayedCarSize, height: displayedCarSize)
        carImageView.center = displayedCarCenter

        CATransaction.commit()
    }

    private func rebuildStaticBackground(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let cached = Self.staticBackgroundCache[key] {
            backgroundImageView.image = cached
            lastBackgroundSize = size
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
            let tc = UIColor.white

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
        lastBackgroundSize = size
    }

    private func loadCarImage() {
        guard !AppDiagnosticsSettings.shouldUseSFRadarCarIcon else { return }
        let key = normalizedCarImageCacheKey
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            CrashLogger.shared.mark("Radar", "loadCarImage:start", details: key)
        }
        if Self.sharedCarImageLoadInFlight.contains(key) { return }
        Self.sharedCarImageLoadInFlight.insert(key)

        guard let url = URL(string: key) else {
            let fallback = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            carOnlineImage = fallback
            carImageView.image = fallback
            return
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { Self.sharedCarImageLoadInFlight.remove(key) }
            guard let data = data, let img = UIImage(data: data) else {
                DispatchQueue.main.async { [weak self] in
                    let fallback = UIImage(systemName: "car.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    self?.carOnlineImage = fallback
                    self?.carImageView.image = fallback
                }
                return
            }

            let finalImage = img
            Self.sharedCarImages[key] = finalImage
            if AppDiagnosticsSettings.isDiagnosticsEnabled {
                CrashLogger.shared.logImageDiagnostics(
                    "RadarCar",
                    width: finalImage.size.width,
                    height: finalImage.size.height,
                    bytes: data.count,
                    note: key
                )
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !AppDiagnosticsSettings.shouldUseSFRadarCarIcon else { return }
                self.currentCarImageCacheKey = key
                self.carOnlineImage = finalImage
                self.carImageView.image = finalImage
                self.updateMarker(force: true)
            }
        }
        task.resume()
    }
}

// MARK: - SwiftUI 封装
struct RadarRepresentable: UIViewRepresentable {
    let locationManager: LocationManager
    var carImageURL: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(locationManager: locationManager)
    }

    final class Coordinator {
        weak var locationManager: LocationManager?
        weak var boundView: RadarUIView?

        init(locationManager: LocationManager) {
            self.locationManager = locationManager
        }

        func bindIfNeeded(to view: RadarUIView) {
            guard boundView !== view else { return }
            boundView = view
            locationManager?.radarPositionHandler = { [weak view] distance, relativeAngle in
                guard let view else { return }
                view.distance = distance
                view.relativeAngle = relativeAngle
                view.updatePosition()
            }
        }
    }

    func makeUIView(context: Context) -> RadarUIView {
        let view = RadarUIView(frame: .zero)
        view.carImageURLString = carImageURL
        context.coordinator.bindIfNeeded(to: view)
        view.distance = locationManager.radarDistance
        view.relativeAngle = locationManager.radarRelativeAngle
        view.updatePosition(force: true)
        return view
    }

    func updateUIView(_ view: RadarUIView, context: Context) {
        context.coordinator.bindIfNeeded(to: view)
        let previousImageURL = view.carImageURLString
        let previousDistance = view.distance
        let previousAngle = view.relativeAngle

        view.carImageURLString = carImageURL
        view.distance = locationManager.radarDistance
        view.relativeAngle = locationManager.radarRelativeAngle

        let shouldForce = previousImageURL != carImageURL
        let shouldUpdatePosition = shouldForce
            || abs(previousDistance - view.distance) >= 0.1
            || abs(previousAngle - view.relativeAngle) >= 0.1

        if shouldUpdatePosition {
            view.updatePosition(force: shouldForce)
        }
    }

    static func dismantleUIView(_ uiView: RadarUIView, coordinator: Coordinator) {
        coordinator.locationManager?.radarPositionHandler = nil
        coordinator.boundView = nil
        uiView.releaseHeavyResources()
    }
}

// MARK: - Radar Card（文字全部用 SwiftUI Text）
struct RadarCardView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    private let displayCacheStore = VehicleDisplayCacheStore()
    var bleStatus: StatusBLEState = .disconnected
    var carLat: Double = 0
    var carLng: Double = 0
    var carAddress: String = ""
    var carImageURL: String = ""

    private var cachedDistanceMeters: Double {
        displayCacheStore.loadSnapshot().distanceMeters
    }

    private var hasActiveBLESession: Bool {
        bleStatus == .connecting || bleStatus == .connected || bleStatus == .authenticating || bleStatus == .authenticated
    }

    private var isLiveAuthenticatedRSSI: Bool {
        bleStatus == .authenticated && !diagnostics.isPreviewRSSI
    }

    private var displayRSSI: Int? {
        diagnostics.debugSmoothedRSSI ?? diagnostics.debugRawRSSI
    }

    private var rssiCenterText: String {
        if let displayRSSI {
            return "\(displayRSSI) dBm"
        }
        return "-- dBm"
    }

    /// 广播预填：灰色；鉴权后 live：按强弱分色
    private var rssiSignalColor: Color {
        guard displayRSSI != nil else { return Color.white.opacity(0.55) }
        if !isLiveAuthenticatedRSSI {
            return Color.white.opacity(0.55)
        }
        guard let displayRSSI else { return Color.white.opacity(0.55) }
        if displayRSSI >= -55 { return AppTheme.green }
        if displayRSSI >= -70 { return AppTheme.orange }
        return AppTheme.red
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RadarRepresentable(locationManager: locationManager, carImageURL: carImageURL)
                    .frame(width: 280, height: 280)

                if hasActiveBLESession {
                    Text(rssiCenterText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(rssiSignalColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(rssiSignalColor.opacity(0.12))
                                .overlay(Capsule().stroke(rssiSignalColor.opacity(0.28), lineWidth: 0.5))
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

            VStack(spacing: 5) {
                if locationManager.distance > 0 {
                    Text(String(format: "距车辆 %.0f 米", locationManager.distance))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                } else if cachedDistanceMeters > 0 {
                    Text(String(format: "距车辆 %.0f 米", cachedDistanceMeters))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                } else if carLat != 0 && carLng != 0 {
                    Text("距离定位中…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                }

                if !locationManager.vehicleAddress.isEmpty {
                    Button {
                        NotificationCenter.default.post(name: .openAddressFloatingWindow, object: nil)
                    } label: {
                        (Text(Image(systemName: "mappin.and.ellipse")) + Text(" \(locationManager.vehicleAddress)"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .layoutPriority(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                } else if carLat != 0 && carLng != 0 {
                    Text("地址解析中…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.36))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }

    private func currentSearchedAddress() -> String {
        let address = locationManager.vehicleAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty { return address }
        guard carLat != 0, carLng != 0 else { return "" }
        return String(format: "%.5f, %.5f", carLat, carLng)
    }

    private func openAmapSearch() {
        guard let url = Self.amapSearchURL(for: currentSearchedAddress()) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func refreshAddress() {
        guard carLat != 0, carLng != 0 else { return }
        locationManager.setCarLocation(lat: carLat, lng: carLng)
    }

    static func amapSearchURL(for keyword: String) -> URL? {
        var components = URLComponents()
        components.scheme = "amap"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return components.url
    }

    @ViewBuilder
    private func addressSettingsFloatingSheet() -> some View {
        VStack {}
    }
}
