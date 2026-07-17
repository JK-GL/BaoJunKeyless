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

    static let defaultCarImageURLString = "https://cdn-df.00bang.cn/images/T1Dw_TBTEv1RCvBVdK.png"
    fileprivate static var sharedCarImages: [String: UIImage] = [:]
    fileprivate static var sharedCarImageLoadInFlight = Set<String>()
    private static var staticBackgroundCache: [String: UIImage] = [:]

    /// 归一化缓存 key：空 URL 时与雷达一致走默认车图。
    static func normalizedCarImageKey(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCarImageURLString : trimmed
    }

    /// 大车图 / 雷达共用内存缓存；命中则不应再闪 SF 占位。
    static func cachedCarImage(for urlString: String) -> UIImage? {
        sharedCarImages[normalizedCarImageKey(urlString)]
    }

    static func storeCarImage(_ image: UIImage, for urlString: String) {
        sharedCarImages[normalizedCarImageKey(urlString)] = image
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            // CrashLogger.shared.mark("Radar", "init") // routine: not error log
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            // CrashLogger.shared.mark("Radar", "init(coder)") // routine: not error log
        }
    }

    deinit {
        markerDisplayLink?.invalidate()
        markerDisplayLink = nil
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if AppDiagnosticsSettings.isDiagnosticsEnabled {
            // CrashLogger.shared.mark("Radar", "deinit") // routine: not error log
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: sz, height: sz) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // 停动画，但保留共享底图/车图，避免切回状态页重建圆盘。
            releaseHeavyResources(clearImages: false)
        } else {
            // 重新入屏：缓存命中则只恢复扫描环，无需重绘底图。
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
                self.releaseHeavyResources(clearImages: true)
            }
        }

        // 首次创建预热 280 静态底图到共享缓存，后续切页直接复用。
        rebuildStaticBackground(CGSize(width: sz, height: sz))
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

    func updatePosition(force: Bool = false) {
        // heading 高频时只更新车标；资源齐全时不要每次 restore。
        if backgroundImageView.image == nil || carImageView.image == nil {
            restoreDynamicResourcesIfNeeded()
        }
        updateMarker(force: force)
    }

    func clearTransientCache() {
        releaseHeavyResources(clearImages: true)
    }

    /// 离屏释放动画；默认保留共享缓存中的底图/车图引用，切回状态页秒开。
    func releaseHeavyResources(clearImages: Bool = false) {
        stopMarkerDisplayLink()
        scanRing1.removeAllAnimations()
        scanRing2.removeAllAnimations()
        carImageView.layer.removeAllAnimations()
        lastDisplayLinkTimestamp = 0
        if clearImages {
            backgroundImageView.image = nil
            carImageView.image = nil
            lastBackgroundSize = .zero
        }
    }

    private func restoreDynamicResourcesIfNeeded() {
        // 圆圈/刻度背景与车图要一起恢复；优先命中共享缓存，避免重绘。
        if bounds.width > 1, bounds.height > 1 {
            if backgroundImageView.image == nil || lastBackgroundSize != bounds.size {
                rebuildStaticBackground(bounds.size)
            }
        } else {
            // 尺寸未定时先用固定雷达尺寸预热共享底图。
            let warmSize = CGSize(width: sz, height: sz)
            if backgroundImageView.image == nil {
                rebuildStaticBackground(warmSize)
            }
            setNeedsLayout()
        }

        if window != nil {
            resumeScanRingAnimationsIfNeeded()
        }
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
        Self.normalizedCarImageKey(carImageURLString)
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
        // 车标跟手平滑恢复 120fps；heading 已在 LocationManager 侧节流。
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
            // CrashLogger.shared.mark("Radar", "rebuildStaticCache", details: key) // routine: not error log
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
            // CrashLogger.shared.mark("Radar", "loadCarImage:start", details: key) // routine: not error log
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
        // 视图将销毁：动画停掉即可，共享缓存继续留给下次创建复用。
        uiView.releaseHeavyResources(clearImages: false)
    }
}

// MARK: - Radar Card
/// 根卡片只观察设置开关（雷达/大车图模式）。
/// locationManager / diagnostics 下沉到子视图：大车图模式时 RSSI 刷新不再整卡重绘。
struct RadarCardView: View {
    /// 不在此 @ObservedObject，避免距离/航向刷新整卡 body。
    let locationManager: LocationManager
    @ObservedObject private var keylessSettings = KeylessSettingsStore.shared
    var bleStatus: StatusBLEState = .disconnected
    var carLat: Double = 0
    var carLng: Double = 0
    var carAddress: String = ""
    var carImageURL: String = ""

    private var showRadar: Bool { keylessSettings.settings.statusRadarEnabled }
    private var showLargeCarImage: Bool { keylessSettings.settings.statusLargeCarImageEnabled }
    private var showProximityStrip: Bool { keylessSettings.settings.statusProximityStripEnabled }

    /// 关系条/大车图都不走雷达 280 方框；关系条再更贴距离文案。
    private var isCompactVisualMode: Bool { showLargeCarImage || showProximityStrip }

    var body: some View {
        // 三模式互斥。关系条参考大车图：不占雷达大方框，上下贴紧。
        VStack(spacing: showProximityStrip ? 4 : 6) {
            if showRadar {
                RadarVisualBlock(
                    locationManager: locationManager,
                    bleStatus: bleStatus,
                    carImageURL: carImageURL
                )
            } else if showLargeCarImage {
                // 完全不观察 RSSI/定位；仅 carImageURL 变化才换图
                StatusLargeCarImageView(carImageURL: carImageURL)
                    .equatable()
                    .frame(maxWidth: .infinity)
            } else if showProximityStrip {
                // 人 — GPS/RSSI — 车；不走雷达背景/280 框。
                // 第三刀：不观察 LocationManager（间距只吃 BLE zone / GPS 远场常量）。
                StatusProximityStripView(
                    bleStatus: bleStatus,
                    carImageURL: carImageURL
                )
            }

            RadarDistanceAddressBlock(
                locationManager: locationManager,
                bleStatus: bleStatus,
                carLat: carLat,
                carLng: carLng
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, showProximityStrip ? 2 : (isCompactVisualMode ? 8 : 8))
        .padding(.bottom, showProximityStrip ? 2 : 8)
        .padding(.horizontal, 16)
    }

    static func amapSearchURL(for keyword: String) -> URL? {
        var components = URLComponents()
        components.scheme = "amap"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return components.url
    }
}

// MARK: - 雷达视觉块（仅雷达模式观察 RSSI/定位）
private struct RadarVisualBlock: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    var bleStatus: StatusBLEState
    var carImageURL: String

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
        if let displayRSSI { return "\(displayRSSI) dBm" }
        return "-- dBm"
    }

    private var rssiSignalColor: Color {
        guard displayRSSI != nil else { return Color.white.opacity(0.55) }
        if !isLiveAuthenticatedRSSI { return Color.white.opacity(0.55) }
        guard let displayRSSI else { return Color.white.opacity(0.55) }
        if displayRSSI >= -55 { return AppTheme.green }
        if displayRSSI >= -70 { return AppTheme.orange }
        return AppTheme.red
    }

    var body: some View {
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
    }
}

// MARK: - 距离/地址块（单独观察；不牵连大车图）
private struct RadarDistanceAddressBlock: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    private let displayCacheStore = VehicleDisplayCacheStore()
    var bleStatus: StatusBLEState
    var carLat: Double
    var carLng: Double

    private var prefersBLEDistance: Bool {
        switch bleStatus {
        case .connected, .authenticating, .authenticated:
            return true
        default:
            return false
        }
    }

    private var isLiveAuthenticatedRSSI: Bool {
        bleStatus == .authenticated && !diagnostics.isPreviewRSSI
    }

    private var displayRSSI: Int? {
        diagnostics.debugSmoothedRSSI ?? diagnostics.debugRawRSSI
    }

    private var bleEstimatedMeters: Double? {
        guard prefersBLEDistance, let rssi = displayRSSI else { return nil }
        return BLEProximityDistanceEstimator.meters(fromRSSI: rssi)
    }

    private var bleDistanceText: String? {
        guard let meters = bleEstimatedMeters else { return nil }
        return BLEProximityDistanceEstimator.displayText(meters: meters)
    }

    private var bleDistanceColor: Color {
        if isLiveAuthenticatedRSSI {
            return rssiSignalColor.opacity(0.95)
        }
        return Color.white.opacity(0.55)
    }

    private var rssiSignalColor: Color {
        guard displayRSSI != nil else { return Color.white.opacity(0.55) }
        if !isLiveAuthenticatedRSSI { return Color.white.opacity(0.55) }
        guard let displayRSSI else { return Color.white.opacity(0.55) }
        if displayRSSI >= -55 { return AppTheme.green }
        if displayRSSI >= -70 { return AppTheme.orange }
        return AppTheme.red
    }

    private var cachedDistanceMeters: Double {
        displayCacheStore.loadSnapshot().distanceMeters
    }

    var body: some View {
        VStack(spacing: 2) {
            if let bleDistanceText {
                Text(bleDistanceText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(bleDistanceColor)
            } else if locationManager.distance > 0 {
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
        .onAppear { syncBLEDistanceOverride() }
        .onChange(of: diagnostics.debugSmoothedRSSI) { _ in syncBLEDistanceOverride() }
        .onChange(of: diagnostics.debugRawRSSI) { _ in syncBLEDistanceOverride() }
        .onChange(of: diagnostics.isPreviewRSSI) { _ in syncBLEDistanceOverride() }
        .onChange(of: bleStatus) { _ in syncBLEDistanceOverride() }
    }

    private func syncBLEDistanceOverride() {
        if prefersBLEDistance, let meters = bleEstimatedMeters {
            locationManager.setBLEDistanceOverride(meters)
        } else {
            locationManager.setBLEDistanceOverride(nil)
        }
    }
}

// MARK: - 人-信号-车 关系条（第三显示模式 · 第三刀性能）
/// 参考大车图：不占雷达框。
/// 第三刀：
/// 1) 不观察 LocationManager（避免 GPS distance 高频重绘整条）
/// 2) 车图独立 Equatable 子视图（RSSI 刷新不重载车图）
/// 3) gap 量化到 2pt，变化小不动画
/// 4) BLE 有估距才用米数；否则固定 GPS 远场 gap
private struct StatusProximityStripView: View {
    @ObservedObject private var diagnostics = BLEDiagnosticsStore.shared
    var bleStatus: StatusBLEState
    var carImageURL: String

    /// 紧凑高度（内容定高）。
    private let stripHeight: CGFloat = 72
    private let carDisplayWidth: CGFloat = 108
    private let personWidth: CGFloat = 36

    private let unlockMeters: CGFloat = 1.5
    private let lockMeters: CGFloat = 8
    private let bleTrustMeters: CGFloat = 25
    private let gapNear: CGFloat = 6
    private let gapGray: CGFloat = 16
    private let gapFar: CGFloat = 28
    private let gapGPS: CGFloat = 40

    private var hasActiveBLESession: Bool {
        bleStatus == .connecting || bleStatus == .connected || bleStatus == .authenticating || bleStatus == .authenticated
    }

    private var prefersBLEDistance: Bool {
        switch bleStatus {
        case .connected, .authenticating, .authenticated: return true
        default: return false
        }
    }

    private var isLiveAuthenticatedRSSI: Bool {
        bleStatus == .authenticated && !diagnostics.isPreviewRSSI
    }

    private var displayRSSI: Int? {
        diagnostics.debugSmoothedRSSI ?? diagnostics.debugRawRSSI
    }

    private var centerText: String {
        if hasActiveBLESession {
            if let displayRSSI { return "\(displayRSSI) dBm" }
            return "-- dBm"
        }
        return "GPS"
    }

    private var centerColor: Color {
        if !hasActiveBLESession { return Color.green.opacity(0.85) }
        guard displayRSSI != nil else { return Color.white.opacity(0.55) }
        if !isLiveAuthenticatedRSSI { return Color.white.opacity(0.55) }
        switch proximityZone {
        case .near: return AppTheme.green
        case .gray: return AppTheme.orange
        case .far: return AppTheme.red
        case .gps: return Color.green.opacity(0.85)
        }
    }

    private enum ProximityZone: Equatable { case near, gray, far, gps }

    /// 单一距离源：仅 BLE 可信时用估距；否则 GPS 远场常量（不读 LocationManager）。
    private var bleMeters: CGFloat? {
        guard prefersBLEDistance, let rssi = displayRSSI,
              let meters = BLEProximityDistanceEstimator.meters(fromRSSI: rssi) else {
            return nil
        }
        return CGFloat(meters)
    }

    private var proximityZone: ProximityZone {
        guard let ble = bleMeters else { return .gps }
        if ble <= unlockMeters { return .near }
        if ble <= lockMeters { return .gray }
        return .far
    }

    private var distanceMetersForGap: CGFloat {
        if let ble = bleMeters { return min(ble, bleTrustMeters) }
        return bleTrustMeters
    }

    private var rawGap: CGFloat {
        switch proximityZone {
        case .gps:
            return gapGPS
        case .near:
            let t = min(max(distanceMetersForGap / unlockMeters, 0), 1)
            return gapNear + (gapGray * 0.55 - gapNear) * t
        case .gray:
            let t = min(max((distanceMetersForGap - unlockMeters) / (lockMeters - unlockMeters), 0), 1)
            let eased = 1 - pow(1 - t, 2)
            return (gapGray * 0.55) + (gapFar - gapGray * 0.55) * eased
        case .far:
            let t = min(max((distanceMetersForGap - lockMeters) / (bleTrustMeters - lockMeters), 0), 1)
            let eased = 1 - pow(1 - t, 1.6)
            return gapFar + (gapGPS - gapFar) * eased
        }
    }

    /// 量化到 2pt：变化 <2pt 不触发动画/布局抖。
    private var quantizedGap: CGFloat {
        (rawGap / 2).rounded() * 2
    }

    private var proximityScale: CGFloat {
        switch proximityZone {
        case .near: return 1.05
        case .gray: return 1.0
        case .far: return 0.96
        case .gps: return 0.94
        }
    }

    private var linkColor: Color {
        centerColor.opacity(proximityZone == .near ? 0.40 : (proximityZone == .gray ? 0.28 : 0.16))
    }

    var body: some View {
        // 仅 anim gap / scale；车图在独立子视图，RSSI 刷新不重载。
        HStack(spacing: quantizedGap) {
            Image(systemName: "figure.stand")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.84))
                .frame(width: personWidth, height: stripHeight)
                .scaleEffect(proximityScale)

            ZStack {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(linkColor)
                        .frame(width: max(quantizedGap * 0.35, 6), height: 1)
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(linkColor)
                        .frame(width: max(quantizedGap * 0.35, 6), height: 1)
                }
                .frame(width: 92)

                Text(centerText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(centerColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.28))
                            .overlay(Capsule().fill(centerColor.opacity(0.14)))
                            .overlay(Capsule().stroke(centerColor.opacity(0.28), lineWidth: 0.5))
                    )
            }
            .frame(minWidth: 76)

            ProximityStripCarImageView(carImageURL: carImageURL)
                .equatable()
                .scaleEffect(proximityScale)
                .frame(width: carDisplayWidth, height: stripHeight - 8)
        }
        .frame(height: stripHeight)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        // 只对量化后的 gap 做动画，避免 RSSI 每个采样都 ease。
        .animation(.easeInOut(duration: 0.18), value: quantizedGap)
        .animation(.easeInOut(duration: 0.18), value: proximityZone)
    }
}

// MARK: - 关系条车图（隔离 RSSI 刷新）
private struct ProximityStripCarImageView: View, Equatable {
    let carImageURL: String
    @State private var displayCarImage: UIImage?

    static func == (lhs: ProximityStripCarImageView, rhs: ProximityStripCarImageView) -> Bool {
        lhs.carImageURL == rhs.carImageURL
    }

    var body: some View {
        Group {
            if let displayCarImage {
                Image(uiImage: displayCarImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: carImageURL) { _ in
            displayCarImage = nil
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        let key = RadarUIView.normalizedCarImageKey(carImageURL)
        if let cached = RadarUIView.cachedCarImage(for: key) {
            displayCarImage = cached.bjk_trimmedTransparentPixels(alphaThreshold: 10) ?? cached
            return
        }
        guard let url = URL(string: key) else { return }
        if RadarUIView.sharedCarImageLoadInFlight.contains(key) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let cached = RadarUIView.cachedCarImage(for: key) {
                    displayCarImage = cached.bjk_trimmedTransparentPixels(alphaThreshold: 10) ?? cached
                } else {
                    loadIfNeeded()
                }
            }
            return
        }
        RadarUIView.sharedCarImageLoadInFlight.insert(key)
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer {
                DispatchQueue.main.async {
                    RadarUIView.sharedCarImageLoadInFlight.remove(key)
                }
            }
            guard let data, let img = UIImage(data: data) else { return }
            RadarUIView.storeCarImage(img, for: key)
            let trimmed = img.bjk_trimmedTransparentPixels(alphaThreshold: 10) ?? img
            DispatchQueue.main.async {
                self.displayCarImage = trimmed
            }
        }.resume()
    }
}

// MARK: - 状态页大车图（与雷达共用 sharedCarImages；不跑雷达动画）
/// 完全对齐 v724 流畅模型：
/// - 外框固定宽高（像 420 框），ScrollView 永不因车图重排
/// - 车图：回退 v729 基准 0.80，再放大 10% → 0.88
/// - 根卡片 / 状态区不再观察高频 RSSI·航向；本视图 Equatable，仅 URL 变化换图
private struct StatusLargeCarImageView: View, Equatable {
    let carImageURL: String
    /// 显示用图（已裁透明边）；与雷达原图缓存分离。
    @State private var displayImage: UIImage?
    @State private var loadToken = 0

    /// 固定外框宽：接近 v724 的稳定大方框（按屏宽估一次，不读图片）。
    private let frameWidthRatio: CGFloat = 1.0
    /// 固定外框高宽比。高度恒定 = 流畅根因。
    private let layoutAspect: CGFloat = 1.95
    /// v729=0.80，再放大 10% → 0.88。
    private let contentScale: CGFloat = 0.88

    static func == (lhs: StatusLargeCarImageView, rhs: StatusLargeCarImageView) -> Bool {
        lhs.carImageURL == rhs.carImageURL
    }

    init(carImageURL: String) {
        self.carImageURL = carImageURL
        if let raw = RadarUIView.cachedCarImage(for: carImageURL) {
            _displayImage = State(initialValue: Self.trimmedDisplayImage(from: raw, cacheKey: carImageURL))
        } else {
            _displayImage = State(initialValue: nil)
        }
    }

    /// 固定外框宽：只依赖屏宽。
    private var frameWidth: CGFloat {
        let screen = UIScreen.main.bounds.width
        let cardInset: CGFloat = 32
        return max(screen - cardInset, 200) * frameWidthRatio
    }

    /// 固定外框高：加载前/后完全一致。
    private var frameHeight: CGFloat {
        frameWidth / layoutAspect
    }

    var body: some View {
        // v724 模型：固定框 + 内容缩放；不改布局尺寸。
        ZStack {
            if let displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(contentScale)
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .scaleEffect(contentScale)
            }
        }
        .frame(width: frameWidth, height: frameHeight)
        .frame(maxWidth: .infinity)
        // 固定框内内容居中；scale 0.8 后上下左右自然留白更宽。
        .onAppear { applyCacheOrLoad() }
        .onChange(of: carImageURL) { _ in
            displayImage = nil
            applyCacheOrLoad()
        }
    }

    private func applyCacheOrLoad() {
        let key = RadarUIView.normalizedCarImageKey(carImageURL)
        if let cached = RadarUIView.cachedCarImage(for: key) {
            displayImage = Self.trimmedDisplayImage(from: cached, cacheKey: key)
            return
        }
        loadIfNeeded(key: key)
    }

    private func loadIfNeeded(key: String) {
        guard let url = URL(string: key) else { return }
        if RadarUIView.sharedCarImageLoadInFlight.contains(key) {
            let token = loadToken + 1
            loadToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard token == loadToken else { return }
                if let cached = RadarUIView.cachedCarImage(for: key) {
                    displayImage = Self.trimmedDisplayImage(from: cached, cacheKey: key)
                } else {
                    loadIfNeeded(key: key)
                }
            }
            return
        }

        RadarUIView.sharedCarImageLoadInFlight.insert(key)
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer {
                DispatchQueue.main.async {
                    RadarUIView.sharedCarImageLoadInFlight.remove(key)
                }
            }
            guard let data, let img = UIImage(data: data) else { return }
            RadarUIView.storeCarImage(img, for: key)
            let trimmed = Self.trimmedDisplayImage(from: img, cacheKey: key)
            DispatchQueue.main.async {
                self.displayImage = trimmed
            }
        }.resume()
    }

    /// 裁透明边缓存：同一 URL 只裁一次。
    private static var trimmedCache: [String: UIImage] = [:]

    private static func trimmedDisplayImage(from image: UIImage, cacheKey: String) -> UIImage {
        let key = RadarUIView.normalizedCarImageKey(cacheKey)
        if let hit = trimmedCache[key] { return hit }
        let trimmed = image.bjk_trimmedTransparentPixels(alphaThreshold: 10) ?? image
        trimmedCache[key] = trimmed
        return trimmed
    }
}

// MARK: - 裁掉官方车图四周透明边（否则“收窄上下”几乎无效）
private extension UIImage {
    /// 返回去掉四周近透明像素后的图；失败返回 nil。
    func bjk_trimmedTransparentPixels(alphaThreshold: UInt8 = 10) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 2, height > 2 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        // 步进采样：大图裁边足够准，比逐像素快。
        let step = max(1, min(width, height) / 400)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let a = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                if a > alphaThreshold {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                x += step
            }
            y += step
        }
        guard found else { return nil }

        // 外扩一点，避免裁到车身边缘锯齿。
        let pad = max(2, step * 2)
        minX = max(0, minX - pad)
        minY = max(0, minY - pad)
        maxX = min(width - 1, maxX + pad)
        maxY = min(height - 1, maxY + pad)

        let cropW = maxX - minX + 1
        let cropH = maxY - minY + 1
        guard cropW > 8, cropH > 8 else { return nil }
        // 几乎无透明边则不裁，省一次拷贝。
        if cropW >= width - 2, cropH >= height - 2 { return self }

        let cropRect = CGRect(x: minX, y: minY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
