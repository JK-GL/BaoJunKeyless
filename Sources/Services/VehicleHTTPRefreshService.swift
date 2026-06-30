import Foundation
import CocoaMQTT

class HTTPRefreshService {
    static let shared = HTTPRefreshService()
    private init() {}

    func pollOnce(store: MQTTVehicleStateStore) {
        let creds = store.credentialsStore
        let token = creds.accessToken
        guard !token.isEmpty else { return }

        SGMWApiClient.shared.queryVehicleStatusResult(accessToken: token) { [weak store] result in
            guard let store else { return }
            DispatchQueue.main.async {
                guard case .success(let payload) = result else { return }
                store.lastHTTPUpdate = Date()
                let newState = store.mapHTTPToVehicleState(payload.carStatus)
                let newDashboard = store.mapHTTPToDashboard(payload.carStatus)
                let shouldUseHTTP = store.lastMQTTUpdate == nil || Date().timeIntervalSince(store.lastMQTTUpdate) >= 60

                store.mergeHTTPBaseState(newState: newState, dashboard: newDashboard)
                if shouldUseHTTP {
                    store.apply(newState)
                    store.applyDashboard(newDashboard)
                }

                store.applyHTTPMeta(carInfo: payload.carInfo, carStatus: payload.carStatus)
                CrashLogger.shared.mark("HTTP", "status updated")
            }
        }
    }

    func fetchBleKeyInfo(store: MQTTVehicleStateStore) {
        let creds = store.credentialsStore
        guard !creds.accessToken.isEmpty, !creds.vin.isEmpty, !creds.phone.isEmpty else { return }
        SGMWApiClient.shared.queryBleKeyResult(accessToken: creds.accessToken, vin: creds.vin, phone: creds.phone) { [weak store] result in
            guard let store else { return }
            DispatchQueue.main.async {
                guard case .success(let info) = result else { return }
                store.latestBleKeyInfo = info
                if store.bleStatus != .connected {
                    store.bleStatus = .disconnected
                }
                var dash = store.dashboard
                dash.bleMacText = info["bleMac"] ?? info["macAddress"] ?? dash.bleMacText
                dash.keyIdText = info["keyId"] ?? dash.keyIdText
                dash.keyTypeText = info["keyType"] ?? dash.keyTypeText
                dash.masterKeyMaskedText = maskHex(info["masterKey"], visiblePrefix: 4, visibleSuffix: 4)
                dash.randomMaskedText = maskHex(info["keyMasterRandom"] ?? info["random"], visiblePrefix: 4, visibleSuffix: 4)
                dash.keyExpiryText = info["expiredTime"] ?? info["expireTime"] ?? info["endTime"] ?? dash.keyExpiryText
                dash.vehicleInfoUpdatedAtText = formatDateTime(Date())
                store.applyDashboard(dash)
            }
        }
    }

    func applyHTTPMeta(carInfo: [String: String], carStatus: [String: String], store: MQTTVehicleStateStore) {
        if let coordinate = VehicleHTTPMetaMapper.coordinate(from: carStatus) {
            store.liveLatitudeGcj = coordinate.latGcj
            store.liveLongitudeGcj = coordinate.lngGcj
            store.cachedLatitudeGcj = coordinate.latGcj
            store.cachedLongitudeGcj = coordinate.lngGcj
            if let addressHint = coordinate.addressHint, !addressHint.isEmpty {
                store.liveAddress = addressHint
                store.cachedAddress = addressHint
                store.persistDisplayCache()
            } else {
                store.persistDisplayCache()
            }
            store.locationResolver.getAddress(gcjLat: coordinate.latGcj, gcjLng: coordinate.lngGcj, address: coordinate.addressHint, amapWebKey: store.addressSettings.amapWebKey) { [weak store] resolved in
                guard let store, let resolved else { return }
                DispatchQueue.main.async {
                    store.liveAddress = resolved
                    store.cachedAddress = resolved
                    store.persistDisplayCache()
                }
            }
        }

        let dash = VehicleHTTPMetaMapper.dashboard(base: store.dashboard, carInfo: carInfo)
        if VehicleHTTPMetaMapper.supportsMQTT(carInfo: carInfo) {
            store.authStatus = .valid
        }
        if !store.latestBleKeyInfo.isEmpty, store.bleStatus == .connecting {
            store.bleStatus = .disconnected
        }
        store.applyDashboard(dash)

        let profile = VehicleHTTPMetaMapper.profile(carInfo: carInfo, carStatus: carStatus)
        store.applyProfile(profile)
    }
}
