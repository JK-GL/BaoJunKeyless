import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var addressSettings: AddressServiceSettings
    @AppStorage(AppDiagnosticsSettings.disableRadarKey) private var disableRadar = false
    @StateObject private var locationManager = LocationManager()
    @State private var isRefreshing = false
    @State private var refreshScale: CGFloat = 1.0
    @State private var isAddressFloatingPresented = false
    @State private var activeCommand: CommandAction? = nil

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
        if settingsStore.settings.pluginTakeover { return "puzzlepiece" }
        if settingsStore.settings.smartSwitch { return "arrow.triangle.2.circlepath" }
        if settingsStore.settings.appManual { return "iphone" }
        return "pause.circle.fill"
    }

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
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
                    QuickActionsView { command in
                        activeCommand = command
                    }
                    RangeCardView()
                    BodyStatusView()
                    StatusDashboardPair {
                        DrivingStatusView()
                    } right: {
                        BatteryGaugesView()
                    }
                    StatusDashboardPair {
                        TemperatureView()
                    } right: {
                        ChargingStatusView()
                    }
                    LightingStatusView()
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

            if isAddressFloatingPresented {
                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { isAddressFloatingPresented = false }
                        }

                    addressFloatingWindow()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
                .zIndex(10)
            }

            // 快捷操作居中弹窗
            if let command = activeCommand {
                CommandConfirmPopup(
                    action: command,
                    vehicleState: .placeholder,
                    isPresented: Binding(
                        get: { activeCommand != nil },
                        set: { if !$0 { activeCommand = nil } }
                    )
                ) { cmd, temp in
                    // 指令执行后的回调
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
                .zIndex(20)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAddressFloatingWindow"))) { _ in
            withAnimation { isAddressFloatingPresented = true }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: activeCommand != nil)
    }

    @ViewBuilder
    private func addressFloatingWindow() -> some View {
        FloatingPopupCard(
            icon: "mappin.and.ellipse",
            iconColor: AppTheme.accent,
            title: "车辆地址",
            subtitle: "查看当前定位并配置高德服务 Key",
            onClose: { withAnimation(.easeOut(duration: 0.2)) { isAddressFloatingPresented = false } }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(locationManager.vehicleAddress)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
                        .layoutPriority(1)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(AppTheme.orange)
                            .frame(width: 20)
                        Text(addressSettings.hasAmapWebKey ? "高德 Key 已填写" : "填写后自动使用高德 API")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                    }

                    TextField("填写高德 Web 服务 Key", text: Binding(
                        get: { addressSettings.amapWebKey },
                        set: { addressSettings.setAmapWebKey($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    HStack {
                        Spacer()
                        Button {
                            addressSettings.clearAmapWebKey()
                        } label: {
                            Text("清除高德 Key")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red.opacity(0.9))
                        }
                    }
                }
            }
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(
                    title: "确定",
                    color: AppTheme.accent
                ) {
                    withAnimation(.easeOut(duration: 0.2)) { isAddressFloatingPresented = false }
                    locationManager.setCarLocation(lat: 22.635842, lng: 114.129604)
                }

                FloatingPopupSecondaryButton(
                    title: "高德",
                    textColor: .white
                ) {
                    let keyword = locationManager.vehicleAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let address = keyword.isEmpty ? "22.635842,114.129604" : keyword
                    let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
                    if let url = URL(string: "amap://search?keyword=\(encoded)"), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }
            }
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
