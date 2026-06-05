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

    func pause() {
        CrashLogger.shared.mark("Motion", "pause")
        manager.stopDeviceMotionUpdates()
    }

    func resume() {
        guard manager.isDeviceMotionAvailable else { return }
        CrashLogger.shared.mark("Motion", "resume")
        if !manager.isDeviceMotionActive {
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let m = motion else { return }
                let smooth = 0.15
                self.pitch += smooth * (m.attitude.pitch - self.pitch)
                self.roll  += smooth * (m.attitude.roll  - self.roll)
            }
        }
    }
}

// MARK: - BLE 蓝牙状态
enum BLEConnectionState {
    case disconnected
    case connecting
    case connected

    var text: String {
        switch self {
        case .disconnected: return "BLE 未连接"
        case .connecting:   return "正在连接 E260-BLE"
        case .connected:    return "已连接 E260-BLE"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return Color.white.opacity(0.45)
        case .connecting:   return AppTheme.orange
        case .connected:    return AppTheme.green
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "dot.radiowaves.left.and.right"
        case .connecting:   return "dot.radiowaves.left.and.right"
        case .connected:    return "dot.radiowaves.left.and.right"
        }
    }
}

struct BLEStatusView: View {
    @State private var bleState: BLEConnectionState = .disconnected

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: bleState.icon)
                .font(.system(size: 12))
            Text(bleState.text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(bleState.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(bleState.color.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Status View (Tab 1)
struct StatusView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @StateObject private var motion = MotionManager()
    @StateObject private var locationManager = LocationManager()
    @State private var isRefreshing = false
    @State private var refreshScale: CGFloat = 1.0

    private var modeText: String {
        if settingsStore.settings.pluginTakeover { return "插件托管" }
        if settingsStore.settings.smartSwitch { return "智能切换" }
        if settingsStore.settings.appManual { return "App 手动" }
        return "未启用"
    }

    private var modeColor: Color {
        if settingsStore.settings.pluginTakeover || settingsStore.settings.smartSwitch { return AppTheme.green }
        if settingsStore.settings.appManual { return AppTheme.orange }
        return Color.white.opacity(0.45)
    }

    private var modeIcon: String {
        if settingsStore.settings.pluginTakeover { return "shield.fill" }
        if settingsStore.settings.smartSwitch { return "arrow.triangle.2.circlepath" }
        if settingsStore.settings.appManual { return "iphone" }
        return "slash.circle"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                StatusTopBarSection(
                    isRefreshing: isRefreshing,
                    refreshScale: refreshScale,
                    onRefresh: handleRefresh
                )

                StatusPillsSection(
                    modeIcon: modeIcon,
                    modeText: modeText,
                    modeColor: modeColor
                )

                RadarCardView(motion: motion, locationManager: locationManager)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            motion.pause()
            locationManager.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            motion.resume()
            locationManager.resume()
        }
    }

    private func handleRefresh() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            refreshScale = 1.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2)) {
                refreshScale = 1.0
                isRefreshing = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRefreshing = false
        }
    }
}
