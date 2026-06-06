import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @AppStorage(AppDiagnosticsSettings.disableRadarKey) private var disableRadar = false
    @StateObject private var locationManager = LocationManager()
    @State private var isRefreshing = false
    @State private var refreshScale: CGFloat = 1.0

    private var modeText: String {
        guard settingsStore.settings.keylessEnabled else { return "无感关闭" }
        if settingsStore.settings.pluginTakeover { return "插件托管" }
        if settingsStore.settings.smartSwitch { return "智能切换" }
        if settingsStore.settings.appManual { return "App手动" }
        return "无感待命"
    }

    private var modeColor: Color {
        guard settingsStore.settings.keylessEnabled else { return Color.white.opacity(0.45) }
        if settingsStore.settings.pluginTakeover { return AppTheme.green }
        if settingsStore.settings.smartSwitch { return AppTheme.accent }
        if settingsStore.settings.appManual { return AppTheme.purple }
        return AppTheme.orange
    }

    private var modeIcon: String {
        guard settingsStore.settings.keylessEnabled else { return "bolt.slash.fill" }
        if settingsStore.settings.pluginTakeover { return "bolt.fill" }
        if settingsStore.settings.smartSwitch { return "arrow.triangle.2.circlepath" }
        if settingsStore.settings.appManual { return "iphone" }
        return "pause.circle.fill"
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

                if disableRadar {
                    CardView(title: "雷达已禁用（诊断模式）", icon: "wave.3.slash", iconColor: AppTheme.orange) {
                        Text("已通过诊断开关关闭雷达，以便隔离内存问题。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    RadarCardView(locationManager: locationManager)
                }
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
            locationManager.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
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
