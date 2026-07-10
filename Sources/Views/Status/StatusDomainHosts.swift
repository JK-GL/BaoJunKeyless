import SwiftUI

struct CarLocationDisplaySnapshot: Equatable {
    let latitude: Double
    let longitude: Double
    let address: String
}

/// 只观察位置显示域 + 连接状态中的 BLE 态，避免整页 StatusView 因 lat/lng/address 变化重算。
struct StatusRadarSection: View {
    @ObservedObject private var locationDisplayStore = VehicleLocationDisplayStore.shared
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    @ObservedObject var locationManager: LocationManager
    let unlockThresholdText: String
    let lockThresholdText: String
    let carImageURL: String

    var body: some View {
        RadarCardView(
            locationManager: locationManager,
            bleStatus: connectionStatusStore.uiBLEStatus,
            unlockThresholdText: unlockThresholdText,
            lockThresholdText: lockThresholdText,
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

/// 顶部胶囊：只观察连接状态中的 BLE/MQTT。
struct StatusPillsHost: View {
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    let modeIcon: String
    let modeText: String
    let modeColor: Color
    let physicalKeyState: StatusPhysicalKeyState
    let gearState: StatusGearState
    let onBLETap: () -> Void
    let onMQTTTap: () -> Void

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

/// MQTT 信息浮窗：只观察连接状态 MQTT 文案，其他显示值由父层传入快照。
struct StatusMQTTFloatingHost: View {
    @ObservedObject private var connectionStatusStore = VehicleConnectionStatusStore.shared
    let broker: String
    let clientId: String
    let username: String
    let password: String
    let tokenSource: String
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
                tokenSource: tokenSource,
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
