import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var addressSettings: AddressServiceSettings
    @AppStorage(AppDiagnosticsSettings.disableRadarKey) private var disableRadar = false
    @AppStorage(AppDiagnosticsSettings.quickActionsDebugModeKey) private var quickActionsDebugMode = true
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var vehicleStore: VehicleStateStore
    @State private var isRefreshing = false
    @State private var refreshScale: CGFloat = 1.0
    @State private var isAddressFloatingPresented = false
    @State private var activeCommand: CommandAction? = nil
    @State private var isEditingAmapKey = false
    @State private var amapKeyDraft = ""


    private var vehicleName: String { "宝骏云海" }

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
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusTopBarSection(
                            vehicleName: vehicleName,
                            isRefreshing: isRefreshing,
                            refreshScale: refreshScale,
                            onRefresh: handleRefresh
                        )

                        VehicleHeaderSummaryView(
                            energyType: vehicleStore.dashboard.energyType,
                            electricRangeKm: vehicleStore.dashboard.electricRangeKm,
                            electricFullRangeKm: vehicleStore.dashboard.electricFullRangeKm,
                            fuelRangeKm: vehicleStore.dashboard.fuelRangeKm,
                            fuelFullRangeKm: vehicleStore.dashboard.fuelFullRangeKm,
                            isCharging: vehicleStore.dashboard.isCharging,
                            chargingPowerText: vehicleStore.dashboard.chargingPowerText,
                            updatedAt: vehicleStore.dashboard.updatedAtText
                        )

                        StatusPillsSection(
                            modeIcon: modeIcon,
                            modeText: modeText,
                            modeColor: modeColor,
                            bleStatus: .connected,
                            doorLockState: vehicleStore.state.locked == true ? .locked : (vehicleStore.state.locked == false ? .unlocked : .unknown),
                            physicalKeyState: vehicleStore.state.physicalKeyInside == true ? .inCar : (vehicleStore.state.physicalKeyInside == false ? .normal : .unknown),
                            gearState: StatusGearState(gear: vehicleStore.state.gear)
                        )
                    }

                    if disableRadar {
                        CardView(title: "雷达已禁用（诊断模式）", icon: "wave.3.slash", iconColor: AppTheme.orange) {
                            Text("已通过诊断开关关闭雷达，以便隔离内存问题。")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        RadarCardView(locationManager: locationManager)
                    }

                    QuickActionsView(onCommand: { command in
                        activeCommand = command
                    }, vehicleState: vehicleStore.state)

                    VStack(alignment: .leading, spacing: 16) {
                        BodyStatusView(dashboard: vehicleStore.dashboard)
                        StatusDashboardPair {
                            DrivingStatusView(metrics: vehicleStore.cachedDashboardMetrics.driving)
                        } right: {
                            BatteryGaugesView(metrics: vehicleStore.cachedDashboardMetrics.battery)
                        }
                        StatusDashboardPair {
                            TemperatureView(metrics: vehicleStore.cachedDashboardMetrics.temperature)
                        } right: {
                            ChargingStatusView(metrics: vehicleStore.cachedDashboardMetrics.charging)
                        }
                        LightingStatusView(metrics: vehicleStore.cachedDashboardMetrics.lighting)
                        VehicleInfoMergedCard()

                        Spacer(minLength: 100)
                    }
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
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { isAddressFloatingPresented = false }
                    }

                addressFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }

            // 快捷操作居中弹窗
            if let command = activeCommand {
                CommandConfirmPopup(
                    action: command,
                    vehicleState: vehicleStore.state,
                    isPresented: Binding(
                        get: { activeCommand != nil },
                        set: { if !$0 { activeCommand = nil } }
                    )
                ) { cmd, temp in
                    handleQuickActionConfirm(action: cmd, temperature: temp)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
                .zIndex(20)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAddressFloatingWindow"))) { _ in
            isEditingAmapKey = false
            amapKeyDraft = addressSettings.amapWebKey
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isAddressFloatingPresented = true }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: activeCommand != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isAddressFloatingPresented)
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text("当前定位")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                        Spacer()
                    }

                    Text(locationManager.vehicleAddress)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(5)
                        .minimumScaleFactor(0.85)
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
                        get: { isEditingAmapKey ? amapKeyDraft : maskedAmapKey },
                        set: { amapKeyDraft = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isEditingAmapKey = true
                            amapKeyDraft = addressSettings.amapWebKey
                        }
                    }

                    HStack(spacing: 10) {
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                addressSettings.clearAmapWebKey()
                                amapKeyDraft = ""
                                isEditingAmapKey = false
                            }
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
                    if isEditingAmapKey {
                        addressSettings.setAmapWebKey(amapKeyDraft)
                    }
                    isEditingAmapKey = false
                    locationManager.setCarLocation(lat: 22.635842, lng: 114.129604)
                }

                FloatingPopupSecondaryButton(
                    title: "高德",
                    textColor: .white
                ) {
                    withAnimation(.easeOut(duration: 0.2)) { isAddressFloatingPresented = false }
                    if isEditingAmapKey {
                        addressSettings.setAmapWebKey(amapKeyDraft)
                    }
                    isEditingAmapKey = false
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

    private var maskedAmapKey: String {
        let key = addressSettings.amapWebKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "" }
        if key.count <= 8 {
            return String(repeating: "•", count: 6)
        }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)******\(suffix)"
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

    private func handleQuickActionConfirm(action: CommandAction, temperature: Double?) {
        if quickActionsDebugMode {
            switch action {
            case .lockUnlock:
                if vehicleStore.state.locked == true {
                    vehicleStore.simulateUnlock()
                } else {
                    vehicleStore.simulateLock()
                }
            case .acToggle:
                vehicleStore.simulateToggleAC()
                if let temperature {
                    vehicleStore.simulateSetACTemperature(temperature)
                }
            case .windowToggle:
                vehicleStore.simulateToggleWindows()
            case .remoteStart:
                vehicleStore.simulateRemoteStart()
            case .findCar:
                break
            case .quickCool:
                vehicleStore.simulateToggleAC()
                vehicleStore.simulateSetACTemperature(temperature ?? 17)
            }
        }
    }
}
