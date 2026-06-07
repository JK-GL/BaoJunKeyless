import SwiftUI

struct StatusView: View {
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var addressSettings: AddressServiceSettings
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
        if settingsStore.settings.pluginTakeover { return "puzzlepiece" }
        if settingsStore.settings.smartSwitch { return "arrow.triangle.2.circlepath" }
        if settingsStore.settings.appManual { return "iphone" }
        return "pause.circle.fill"
    }

    var body: some View {
        ZStack {
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
                            .environmentObject(addressSettings)
                    }
                    QuickActionsView()
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
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isAddressFloatingPresented = false } }

                VStack(spacing: 0) {
                    Spacer()
                    addressFloatingWindow()
                }
                .transition(.move(edge: .bottom))
                .padding(.horizontal, 0)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isAddressFloatingPresented)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAddressFloatingWindow"))) { _ in
            withAnimation { isAddressFloatingPresented = true }
        }
    }

    @ViewBuilder
    private func addressFloatingWindow() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("车辆地址")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(locationManager.vehicleAddress)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .layoutPriority(1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "map")
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)
                    Text("地址解析方式")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                }

                Picker("地址解析方式", selection: Binding(
                    get: { addressSettings.provider },
                    set: { addressSettings.provider = $0 }
                )) {
                    ForEach(AddressServiceType.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("高德 Web 服务 Key", text: Binding(
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

            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isAddressFloatingPresented = false }
                    locationManager.setCarLocation(lat: 22.635842, lng: 114.129604)
                } label: {
                    Text("确定")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.accent))
                }

                Button {
                    let keyword = locationManager.vehicleAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let address = keyword.isEmpty ? "22.635842,114.129604" : keyword
                    if let url = URL(string: "amap://search?keyword=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("高德")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isAddressFloatingPresented = false }
                } label: {
                    Text("完成")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 0)
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
