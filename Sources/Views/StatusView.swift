import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var addressSettings: AddressServiceSettings
    @AppStorage(AppDiagnosticsSettings.disableRadarKey) private var disableRadar = false
    @AppStorage(AppDiagnosticsSettings.quickActionsDebugModeKey) private var quickActionsDebugMode = false
    @StateObject private var locationManager = LocationManager()
    @StateObject private var mockVehicleState = MockVehicleStateStore()
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
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusTopBarSection(
                            vehicleName: vehicleName,
                            isRefreshing: isRefreshing,
                            refreshScale: refreshScale,
                            onRefresh: handleRefresh
                        )

                        VehicleHeaderSummaryView(
                            electricRangeKm: mockVehicleState.dashboard.electricRangeKm,
                            electricFullRangeKm: mockVehicleState.dashboard.electricFullRangeKm,
                            fuelRangeKm: mockVehicleState.dashboard.fuelRangeKm,
                            fuelFullRangeKm: mockVehicleState.dashboard.fuelFullRangeKm,
                            isCharging: mockVehicleState.dashboard.isCharging,
                            chargingPowerText: mockVehicleState.dashboard.chargingPowerText,
                            updatedAt: mockVehicleState.dashboard.updatedAtText
                        )

                        StatusPillsSection(
                            modeIcon: modeIcon,
                            modeText: modeText,
                            modeColor: modeColor,
                            bleStatus: .connected,
                            doorLockState: mockVehicleState.state.locked == true ? .locked : (mockVehicleState.state.locked == false ? .unlocked : .unknown),
                            physicalKeyState: mockVehicleState.state.physicalKeyInside == true ? .inCar : (mockVehicleState.state.physicalKeyInside == false ? .normal : .unknown),
                            gearState: StatusGearState(gear: mockVehicleState.state.gear)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $quickActionsDebugMode) {
                            Label("快捷操作调试模式", systemImage: "wrench.and.screwdriver")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .tint(AppTheme.orange)

                        Text("打开后，快捷操作会同步切换状态页卡片，便于 UI 联调。")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.035))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 18)

                    QuickActionsView(onCommand: { command in
                        activeCommand = command
                    }, vehicleState: mockVehicleState.state)

                    VStack(alignment: .leading, spacing: 16) {
                        BodyStatusView(dashboard: mockVehicleState.dashboard)
                        StatusDashboardPair {
                            DrivingStatusView(metrics: mockVehicleState.cachedDashboardMetrics.driving)
                        } right: {
                            BatteryGaugesView(metrics: mockVehicleState.cachedDashboardMetrics.battery)
                        }
                        StatusDashboardPair {
                            TemperatureView(metrics: mockVehicleState.cachedDashboardMetrics.temperature)
                        } right: {
                            ChargingStatusView(metrics: mockVehicleState.cachedDashboardMetrics.charging)
                        }
                        LightingStatusView(metrics: mockVehicleState.cachedDashboardMetrics.lighting)
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
                    vehicleState: mockVehicleState.state,
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
                if mockVehicleState.state.locked == true {
                    mockVehicleState.simulateUnlock()
                } else {
                    mockVehicleState.simulateLock()
                }
            case .acToggle:
                mockVehicleState.simulateToggleAC()
                if let temperature {
                    mockVehicleState.simulateSetACTemperature(temperature)
                }
            case .windowToggle:
                mockVehicleState.simulateToggleWindows()
            case .remoteStart:
                mockVehicleState.simulateRemoteStart()
            case .findCar:
                break
            case .quickCool:
                mockVehicleState.simulateToggleAC()
                mockVehicleState.simulateSetACTemperature(temperature ?? 17)
            }
        }
    }
}
