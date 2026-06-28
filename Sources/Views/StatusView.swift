import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var addressSettings: AddressServiceSettings
    @EnvironmentObject var locationManager: LocationManager
    @AppStorage(AppDiagnosticsSettings.disableRadarKey) private var disableRadar = false
    @EnvironmentObject var vehicleStore: VehicleStateStore
    @State private var isRefreshing = false
    @State private var refreshScale: CGFloat = 1.0
    @State private var isAddressFloatingPresented = false
    @State private var isMQTTFloatingPresented = false
    @State private var isVehicleInfoFloatingPresented = false
    @State private var activeCommand: CommandAction? = nil
    @State private var isEditingAmapKey = false
    @State private var amapKeyDraft = ""


    private var mqttStore: MQTTVehicleStateStore? {
        vehicleStore as? MQTTVehicleStateStore
    }

    private var mqttAuthStatus: StatusAuthState {
        mqttStore?.authStatus ?? .expired("未配置")
    }

    private var liveBLEStatus: StatusBLEState {
        switch mqttStore?.bleStatus {
        case .connected:
            return .connected
        case .connecting:
            return .scanning
        case .error:
            return .error
        case .disconnected, .none:
            return .disconnected
        }
    }

    private var liveMQTTStatus: StatusMQTTState {
        switch mqttStore?.mqttStatus {
        case .connected:
            return .connected
        case .connecting:
            return .connecting
        case .error:
            return .error
        case .disconnected, .none:
            return .disconnected
        }
    }

    private var topBarTitle: String {
        let name = vehicleStore.dashboard.vehicleName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "车辆状态" : name
    }

    private var mqttDisplayClientId: String {
        mqttStore?.mqttClientId ?? "--"
    }

    private var mqttDisplayBroker: String {
        mqttStore?.mqttBrokerDisplayText ?? "parkingdata.sgmwcloud.com.cn:1883"
    }

    private var mqttDisplayUsername: String {
        mqttStore?.mqttUsernameMasked ?? "--"
    }

    private var mqttDisplayPassword: String {
        mqttStore?.mqttPasswordMasked ?? "--"
    }

    private var mqttTopicRows: [String] {
        mqttStore?.mqttTopics ?? []
    }

    private var mqttTokenSourceText: String {
        if let source = mqttStore?.tokenSource {
            return source.displayText
        }
        return "未配置 / 未读取"
    }

    private var displayCarLatitude: Double {
        mqttStore?.displayLatitudeGcj ?? 0
    }

    private var displayCarLongitude: Double {
        mqttStore?.displayLongitudeGcj ?? 0
    }

    private var displayCarAddress: String {
        mqttStore?.displayAddress ?? ""
    }

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
                            vehicleName: topBarTitle,
                            isRefreshing: isRefreshing,
                            refreshScale: refreshScale,
                            authStatus: mqttAuthStatus,
                            onRefresh: handleRefresh
                        )

                        VehicleHeaderSummaryView(
                            energyType: vehicleStore.dashboard.energyType,
                            electricRangeKm: vehicleStore.dashboard.electricRangeKm,
                            electricFullRangeKm: vehicleStore.dashboard.electricFullRangeKm,
                            fuelRangeKm: vehicleStore.dashboard.fuelRangeKm,
                            fuelFullRangeKm: vehicleStore.dashboard.fuelFullRangeKm,
                            batteryPercentValue: vehicleStore.dashboard.batteryPercentValue,
                            fuelPercentValue: vehicleStore.dashboard.fuelPercentValue,
                            isCharging: vehicleStore.dashboard.isCharging,
                            chargingPowerText: vehicleStore.dashboard.chargingPowerText,
                            updatedAt: vehicleStore.dashboard.updatedAtText
                        )

                        StatusPillsSection(
                            modeIcon: modeIcon,
                            modeText: modeText,
                            modeColor: modeColor,
                            bleStatus: liveBLEStatus,
                            mqttStatus: liveMQTTStatus,
                            physicalKeyState: {
                                switch vehicleStore.state.physicalKeyPosition {
                                case .inside: return .inCar
                                case .outside: return .outside
                                case .farAway: return .farAway
                                case .unknown: return .unknown
                                }
                            }(),
                            gearState: StatusGearState(gear: vehicleStore.state.gear),
                            onBLETap: { isVehicleInfoFloatingPresented = true },
                            onMQTTTap: { isMQTTFloatingPresented = true }
                        )
                    }

                    if disableRadar {
                        CardView(title: "雷达已禁用（诊断模式）", icon: "wave.3.slash", iconColor: AppTheme.orange) {
                            Text("已通过诊断开关关闭雷达，以便隔离内存问题。")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        RadarCardView(
                            locationManager: locationManager,
                            bleConnected: liveBLEStatus == .connected,
                            carLat: displayCarLatitude,
                            carLng: displayCarLongitude,
                            carAddress: displayCarAddress,
                            carImageURL: vehicleStore.dashboard.vehicleImageURL
                        )
                    }

                    QuickActionsView(onCommand: { command in
                        activeCommand = command
                    }, vehicleState: vehicleStore.state)

                    QuickStatusTripletView(
                        totalMileageText: vehicleStore.dashboard.totalMileageText,
                        averageFuelConsumptionText: vehicleStore.dashboard.averageFuelConsumptionText,
                        yesterdayMileageText: vehicleStore.dashboard.yesterdayMileageText
                    )

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

            if isMQTTFloatingPresented {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { isMQTTFloatingPresented = false }
                    }

                mqttFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(12)
            }

            if isVehicleInfoFloatingPresented {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { isVehicleInfoFloatingPresented = false }
                    }

                vehicleInfoFloatingWindow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(14)
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
        .onReceive(NotificationCenter.default.publisher(for: .openAddressFloatingWindow)) { _ in
            isEditingAmapKey = false
            amapKeyDraft = addressSettings.amapWebKey
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isAddressFloatingPresented = true }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: activeCommand != nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isAddressFloatingPresented)
        .onAppear {
            syncCarLocationToManager(forceAddressRefresh: true)
        }
        .onChange(of: displayCarLatitude) { _ in
            syncCarLocationToManager(forceAddressRefresh: false)
        }
        .onChange(of: displayCarLongitude) { _ in
            syncCarLocationToManager(forceAddressRefresh: false)
        }
        .onChange(of: displayCarAddress) { _ in
            syncCarLocationToManager(forceAddressRefresh: true)
        }
    }

    @ViewBuilder
    private func mqttFloatingWindow() -> some View {
        FloatingPopupCard(
            icon: liveMQTTStatus.icon,
            iconColor: liveMQTTStatus.color,
            title: "MQTT 信息"
        ) {
            MQTTInfoMergedCard(
                status: liveMQTTStatus,
                broker: mqttDisplayBroker,
                clientId: mqttDisplayClientId,
                username: mqttDisplayUsername,
                password: mqttDisplayPassword,
                tokenSource: mqttTokenSourceText,
                topics: mqttTopicRows
            )
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(title: "重新连接", color: AppTheme.accent) {
                    mqttStore?.reconnect()
                }
                FloatingPopupSecondaryButton(title: "关闭", textColor: .white) {
                    withAnimation(.easeOut(duration: 0.2)) { isMQTTFloatingPresented = false }
                }
            }
        }
    }

    @ViewBuilder
    private func vehicleInfoFloatingWindow() -> some View {
        FloatingPopupCard(
            icon: liveBLEStatus.icon,
            iconColor: liveBLEStatus.color,
            title: "车辆信息"
        ) {
            VehicleInfoMergedCard(dashboard: vehicleStore.dashboard, isEmbedded: false)
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(title: "刷新信息", color: AppTheme.accent) {
                    mqttStore?.refreshNow()
                }
                FloatingPopupSecondaryButton(title: "关闭", textColor: .white) {
                    withAnimation(.easeOut(duration: 0.2)) { isVehicleInfoFloatingPresented = false }
                }
            }
        }
    }

    private func syncCarLocationToManager(forceAddressRefresh: Bool) {
        guard displayCarLatitude != 0, displayCarLongitude != 0 else { return }
        let address = forceAddressRefresh ? (displayCarAddress.isEmpty ? nil : displayCarAddress) : nil
        locationManager.setCarLocation(lat: displayCarLatitude, lng: displayCarLongitude, address: address)
    }

    @ViewBuilder
    private func addressFloatingWindow() -> some View {
        FloatingPopupCard(
            icon: "mappin.and.ellipse",
            iconColor: AppTheme.accent,
            title: "车辆地址"
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
                    let lat = mqttStore?.displayLatitudeGcj ?? 0
                    let lng = mqttStore?.displayLongitudeGcj ?? 0
                    if lat != 0, lng != 0 {
                        locationManager.setCarLocation(lat: lat, lng: lng, address: displayCarAddress.isEmpty ? nil : displayCarAddress)
                    }
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
                    let fallbackLat = mqttStore?.displayLatitudeGcj ?? 0
                    let fallbackLng = mqttStore?.displayLongitudeGcj ?? 0
                    let address = keyword.isEmpty ? (fallbackLat != 0 && fallbackLng != 0 ? "\(fallbackLat),\(fallbackLng)" : "") : keyword
                    guard !address.isEmpty else { return }
                    let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
                    if let url = URL(string: "amap://search?keyword=\(encoded)"), UIApplication.shared.canOpenURL(url) {
                        UIApplication.shared.open(url)
                    }
                }

                FloatingPopupSecondaryButton(
                    title: "关闭",
                    textColor: .white
                ) {
                    withAnimation(.easeOut(duration: 0.2)) { isAddressFloatingPresented = false }
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

        locationManager.forceRequestCurrentLocation()
        locationManager.resume()
        syncCarLocationToManager(forceAddressRefresh: true)
        mqttStore?.refreshNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRefreshing = false
        }
    }

    private func handleQuickActionConfirm(action: CommandAction, temperature: Double?) {
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
