import SwiftUI
import UIKit

struct CarLocationDisplaySnapshot: Equatable {
    let latitude: Double
    let longitude: Double
    let address: String
}

/// 只观察位置显示域 + 连接状态 BLE 态 + RSSI 诊断域，避免整页 StatusView 重算。
struct StatusRadarSection: View {
    @ObservedObject private var locationDisplayStore = VehicleLocationDisplayStore.shared
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    @ObservedObject var locationManager: LocationManager
    let carImageURL: String

    var body: some View {
        RadarCardView(
            locationManager: locationManager,
            bleStatus: connectionStatusStore.uiBLEStatus,
            carLat: locationDisplayStore.displayLatitudeGcj,
            carLng: locationDisplayStore.displayLongitudeGcj,
            carAddress: locationDisplayStore.displayAddress,
            carImageURL: carImageURL
        )
    }
}

/// 顶部认证角标：只观察连接状态中的 auth。
struct StatusTopBarHost: View {
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    let vehicleName: String
    let isRefreshing: Bool
    let refreshScale: CGFloat
    let onRefresh: () -> Void

    var body: some View {
        StatusTopBarSection(
            vehicleName: vehicleName,
            isRefreshing: isRefreshing,
            refreshScale: refreshScale,
            authStatus: connectionStatusStore.authStatus,
            onRefresh: onRefresh
        )
    }
}

/// 顶部胶囊：观察连接状态 BLE/MQTT + 无感模式设置，避免根视图计算模式文案。
struct StatusPillsHost: View {
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    let physicalKeyState: StatusPhysicalKeyState
    let gearState: StatusGearState
    let onBLETap: () -> Void
    let onMQTTTap: () -> Void

    private var modeText: String {
        guard settingsStore.settings.keylessEnabled else { return "无感关闭" }
        if settingsStore.settings.pluginTakeover { return "插件托管" }
        if settingsStore.settings.smartSwitch { return "智能切换" }
        if settingsStore.settings.appManual { return "前台手动" }
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
        StatusPillsSection(
            modeIcon: modeIcon,
            modeText: modeText,
            modeColor: modeColor,
            bleStatus: connectionStatusStore.uiBLEStatus,
            mqttStatus: connectionStatusStore.uiMQTTStatus,
            physicalKeyState: physicalKeyState,
            gearState: gearState,
            onBLETap: onBLETap,
            onMQTTTap: onMQTTTap
        )
    }
}

/// 位置同步桥：只在位置显示域变化时同步到 LocationManager。
struct StatusLocationSyncBridge: View {
    @ObservedObject private var locationDisplayStore = VehicleLocationDisplayStore.shared
    @EnvironmentObject var locationManager: LocationManager
    @State private var lastSyncedSnapshot: CarLocationDisplaySnapshot?

    private var snapshot: CarLocationDisplaySnapshot {
        CarLocationDisplaySnapshot(
            latitude: locationDisplayStore.displayLatitudeGcj,
            longitude: locationDisplayStore.displayLongitudeGcj,
            address: locationDisplayStore.displayAddress
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                sync(snapshot: snapshot, forceAddressRefresh: true)
            }
            .onChange(of: snapshot) { next in
                let lastAddress = lastSyncedSnapshot?.address ?? ""
                sync(snapshot: next, forceAddressRefresh: next.address != lastAddress)
            }
    }

    private func sync(snapshot: CarLocationDisplaySnapshot, forceAddressRefresh: Bool) {
        guard snapshot.latitude != 0, snapshot.longitude != 0 else { return }
        let address = forceAddressRefresh ? (snapshot.address.isEmpty ? nil : snapshot.address) : nil
        locationManager.setCarLocation(lat: snapshot.latitude, lng: snapshot.longitude, address: address)
        lastSyncedSnapshot = snapshot
    }
}

/// 控制回执桥：只在回执域变化时通知父视图。
struct StatusControlFeedbackBridge: View {
    @ObservedObject private var controlFeedbackStore = VehicleControlFeedbackStore.shared
    let onMQTTControlResult: (VehicleControlMQTTResult?) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: controlFeedbackStore.latestControlResult) { result in
                onMQTTControlResult(result)
            }
    }
}

/// 钥匙信息弹窗内容：观察控制回执 + 连接状态 BLE 文案。
struct StatusVehicleInfoCardHost: View {
    @ObservedObject private var controlFeedbackStore = VehicleControlFeedbackStore.shared
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    let dashboard: VehicleDashboardState
    let isEmbedded: Bool

    var body: some View {
        VehicleInfoMergedCard(
            dashboard: dashboard,
            bleStatusText: connectionStatusStore.uiBLEStatus.text,
            latestBLEControlText: controlFeedbackStore.latestBLEControlReceipt?.displayDetail ?? "--",
            isEmbedded: isEmbedded
        )
    }
}

/// MQTT 信息浮窗：只观察连接状态 MQTT 文案 + token 来源。
struct StatusMQTTFloatingHost: View {
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    @ObservedObject private var tokenSourceStore = VehicleTokenSourceStore.shared
    let broker: String
    let clientId: String
    let username: String
    let password: String
    let topics: [String]
    let onReconnect: () -> Void
    let onClose: () -> Void

    var body: some View {
        FloatingPopupCard(
            icon: connectionStatusStore.uiMQTTStatus.icon,
            iconColor: connectionStatusStore.uiMQTTStatus.color,
            title: "MQTT 信息",
            maxWidth: 332,
            maxContentHeight: 400,
            fixedContentHeight: 360
        ) {
            MQTTInfoMergedCard(
                status: connectionStatusStore.uiMQTTStatus,
                broker: broker,
                clientId: clientId,
                username: username,
                password: password,
                tokenSource: tokenSourceStore.displayText,
                topics: topics
            )
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(title: "重新连接", color: AppTheme.accent, action: onReconnect)
                FloatingPopupSecondaryButton(title: "关闭", textColor: .white, action: onClose)
            }
        }
    }
}

/// 钥匙信息浮窗：只观察连接状态 BLE 文案 + 控制回执。
struct StatusVehicleInfoFloatingHost: View {
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    let dashboard: VehicleDashboardState
    let nearbyStore: NearbyBLEDevicesStore?
    let onToggleScanning: () -> Void
    let onOpenNearby: () -> Void
    let onFetchKey: () -> Void
    let onRefreshVehicle: () -> Void
    let onClose: () -> Void

    private var isScanning: Bool {
        let status = connectionStatusStore.uiBLEStatus
        return status == .scanning || status == .connecting || status == .authenticating || status == .authenticated
    }

    var body: some View {
        FloatingPopupCard(
            icon: connectionStatusStore.uiBLEStatus.icon,
            iconColor: connectionStatusStore.uiBLEStatus.color,
            title: "钥匙信息",
            contentScrollEnabled: false
        ) {
            StatusVehicleInfoCardHost(
                dashboard: dashboard,
                isEmbedded: false
            )
        } actions: {
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    PopupActionGridButton(
                        title: isScanning ? "停止扫描" : "开始扫描",
                        icon: isScanning ? "stop.circle" : "play.circle",
                        tint: isScanning ? AppTheme.red : AppTheme.accent,
                        action: onToggleScanning
                    )
                    if let nearbyStore {
                        NearbyBLEDevicesLaunchButton(nearbyStore: nearbyStore, action: onOpenNearby)
                    } else {
                        PopupActionGridButton(
                            title: "附近设备",
                            icon: "dot.radiowaves.left.and.right",
                            tint: AppTheme.orange,
                            action: onOpenNearby
                        )
                    }
                    PopupActionGridButton(
                        title: "拉取钥匙",
                        icon: "key.fill",
                        tint: AppTheme.green,
                        action: onFetchKey
                    )
                    PopupActionGridButton(
                        title: "刷新车况",
                        icon: "arrow.clockwise",
                        tint: AppTheme.accent,
                        action: onRefreshVehicle
                    )
                }
                FloatingPopupSecondaryButton(title: "关闭", textColor: .white, action: onClose)
            }
        }
    }
}

/// 地址弹窗：独立宿主，避免地址编辑状态和地址设置牵连 StatusView 根树。
struct StatusAddressFloatingHost: View {
    @EnvironmentObject var addressSettings: AddressServiceSettings
    @EnvironmentObject var locationManager: LocationManager
    @Binding var isPresented: Bool
    @State private var isEditingAmapKey = false
    @State private var amapKeyDraft = ""

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

    var body: some View {
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
                    withAnimation(PopupMotion.dismissEase) { isPresented = false }
                    if isEditingAmapKey {
                        addressSettings.setAmapWebKey(amapKeyDraft)
                    }
                    isEditingAmapKey = false
                    let location = VehicleLocationDisplayStore.shared
                    let lat = location.displayLatitudeGcj
                    let lng = location.displayLongitudeGcj
                    let address = location.displayAddress
                    if lat != 0, lng != 0 {
                        locationManager.setCarLocation(lat: lat, lng: lng, address: address.isEmpty ? nil : address)
                    }
                }

                FloatingPopupSecondaryButton(
                    title: "高德",
                    textColor: .white
                ) {
                    withAnimation(PopupMotion.dismissEase) { isPresented = false }
                    if isEditingAmapKey {
                        addressSettings.setAmapWebKey(amapKeyDraft)
                    }
                    isEditingAmapKey = false
                    let keyword = locationManager.vehicleAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    let location = VehicleLocationDisplayStore.shared
                    let fallbackLat = location.displayLatitudeGcj
                    let fallbackLng = location.displayLongitudeGcj
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
                    withAnimation(PopupMotion.dismissEase) { isPresented = false }
                }
            }
        }
        .onAppear {
            isEditingAmapKey = false
            amapKeyDraft = addressSettings.amapWebKey
        }
    }
}

/// 快捷命令弹窗宿主：只在需要时挂命令状态，不让根视图长期持有命令编辑态之外的多余依赖。
struct StatusCommandConfirmHost: View {
    let action: CommandAction
    let vehicleState: VehicleState
    @Binding var isPresented: Bool
    let onConfirm: (CommandAction, Double?, Int?, @escaping (VehicleCommandExecutionResult) -> Void) -> Void

    var body: some View {
        CommandConfirmPopup(
            action: action,
            vehicleState: vehicleState,
            isPresented: $isPresented,
            onConfirm: onConfirm
        )
    }
}

