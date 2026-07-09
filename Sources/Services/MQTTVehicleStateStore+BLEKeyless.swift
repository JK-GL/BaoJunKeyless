import Foundation

extension MQTTVehicleStateStore {
    func reloadCachedBLEKeyInfo(preferScoped: Bool) {
        if preferScoped, let scope = currentBLEKeyCacheScope() {
            latestBleKeyInfo = VehicleBLEKeyCacheStore.load(vin: scope.vin, phone: scope.phone) ?? [:]
            return
        }
        latestBleKeyInfo = VehicleBLEKeyCacheStore.loadLastActive() ?? [:]
    }

    func currentBLEKeyCacheScope() -> (vin: String, phone: String)? {
        let vin = credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = credentialsStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vin.isEmpty, !phone.isEmpty else { return nil }
        return (vin, phone)
    }

    func persistBLEKeyInfo(_ info: [String: String]) {
        guard let scope = currentBLEKeyCacheScope() else { return }
        VehicleBLEKeyCacheStore.save(info, vin: scope.vin, phone: scope.phone)
    }

    func clearCurrentBLEKeyInfo() {
        if let scope = currentBLEKeyCacheScope() {
            VehicleBLEKeyCacheStore.clear(vin: scope.vin, phone: scope.phone)
        } else {
            VehicleBLEKeyCacheStore.clearLastActive()
        }
        latestBleKeyInfo = [:]
    }

    func logVehicleEvent(
        _ category: VehicleEventLogCategory,
        _ title: String,
        detail: String = "",
        identity: String? = nil,
        minimumInterval: TimeInterval = 2
    ) {
        vehicleEventLogStore.addThrottled(category, title, detail: detail, identity: identity, minimumInterval: minimumInterval)
    }

    func fetchBleKeyInfo() {
        let store = credentialsStore
        guard !store.accessToken.isEmpty, !store.vin.isEmpty, !store.phone.isEmpty else {
            reloadCachedBLEKeyInfo(preferScoped: true)
            if !latestBleKeyInfo.isEmpty {
                refreshBLESessionIfNeeded()
            }
            return
        }
        SGMWApiClient.shared.queryBleKeyResult(accessToken: store.accessToken, vin: store.vin, phone: store.phone) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard case .success(let info) = result else {
                    self.reloadCachedBLEKeyInfo(preferScoped: true)
                    if !self.latestBleKeyInfo.isEmpty {
                        self.refreshBLESessionIfNeeded()
                    }
                    return
                }
                self.persistBLEKeyInfo(info)
                self.latestBleKeyInfo = info
                self.refreshBLESessionIfNeeded()
                var dash = self.dashboard
                dash.bleMacText = info["bleMac"] ?? info["macAddress"] ?? dash.bleMacText
                dash.keyIdText = info["keyId"] ?? dash.keyIdText
                dash.keyTypeText = info["keyType"] ?? dash.keyTypeText
                dash.masterKeyMaskedText = maskHex(info["masterKey"], visiblePrefix: 4, visibleSuffix: 4)
                dash.randomMaskedText = maskHex(info["keyMasterRandom"] ?? info["random"], visiblePrefix: 4, visibleSuffix: 4)
                dash.keyExpiryText = info["expiredTime"] ?? info["expireTime"] ?? info["endTime"] ?? dash.keyExpiryText
                dash.vehicleInfoUpdatedAtText = formatDateTime(Date())
                self.applyDashboard(dash)
            }
        }
    }

    func formatElapsedSince(_ start: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed < 60 { return "\(elapsed)s" }
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return "\(minutes)m\(seconds)s"
    }

    var deviceDisplayName: String {
        let mac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? ""
        let cleaned = mac.uppercased().filter { $0.isLetter || $0.isNumber }
        if cleaned.count >= 12 {
            var parts: [String] = []
            for i in stride(from: 0, to: 12, by: 2) {
                let start = cleaned.index(cleaned.startIndex, offsetBy: i)
                let end = cleaned.index(start, offsetBy: 2)
                parts.append(String(cleaned[start..<end]))
            }
            return parts.joined(separator: ":")
        }
        return mac.isEmpty ? "--" : mac
    }

    func toggleBLEScanning() {
        let isActive = bleStatus == .scanning || bleStatus == .connecting || bleStatus == .authenticating || bleStatus == .authenticated
        if isActive {
            userManuallyStoppedBLE = true
            bleStatus = .disconnected
            bleManager.stop()
            vehicleEventLogStore.add(.action, "BLE 手动停止", detail: "用户取消扫描")
        } else {
            consecutiveScanTimeouts = 0
            userManuallyStoppedBLE = false
            ensureBLESession(forceRestart: true, optimisticScanning: true)
            vehicleEventLogStore.add(.action, "BLE 手动扫描", detail: "用户触发扫描")
        }
    }
}
