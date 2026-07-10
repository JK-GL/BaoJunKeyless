import SwiftUI

struct CarLocationDisplaySnapshot: Equatable {
    let latitude: Double
    let longitude: Double
    let address: String
}

/// 只观察位置显示域，避免整页 StatusView 因 lat/lng/address 变化重算。
struct StatusRadarSection: View {
    @ObservedObject private var locationDisplayStore = VehicleLocationDisplayStore.shared
    @ObservedObject var locationManager: LocationManager
    let bleStatus: StatusBLEState
    let unlockThresholdText: String
    let lockThresholdText: String
    let carImageURL: String

    var body: some View {
        RadarCardView(
            locationManager: locationManager,
            bleStatus: bleStatus,
            unlockThresholdText: unlockThresholdText,
            lockThresholdText: lockThresholdText,
            carLat: locationDisplayStore.displayLatitudeGcj,
            carLng: locationDisplayStore.displayLongitudeGcj,
            carAddress: locationDisplayStore.displayAddress,
            carImageURL: carImageURL
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

/// 钥匙信息弹窗内容：仅观察控制回执域中的 BLE 回执文本。
struct StatusVehicleInfoCardHost: View {
    @ObservedObject private var controlFeedbackStore = VehicleControlFeedbackStore.shared
    let dashboard: VehicleDashboardState
    let bleStatusText: String
    let isEmbedded: Bool

    var body: some View {
        VehicleInfoMergedCard(
            dashboard: dashboard,
            bleStatusText: bleStatusText,
            latestBLEControlText: controlFeedbackStore.latestBLEControlReceipt?.displayDetail ?? "--",
            isEmbedded: isEmbedded
        )
    }
}
