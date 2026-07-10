import Foundation

extension MQTTVehicleStateStore {
    func reloadCachedBLEKeyInfo(preferScoped: Bool) {
        if preferScoped, let scope = currentBLEKeyCacheScope() {
            latestBleKeyInfo = VehicleBLEKeyCacheStore.load(vin: scope.vin, phone: scope.phone) ?? [:]
        } else {
            latestBleKeyInfo = VehicleBLEKeyCacheStore.loadLastActive() ?? [:]
        }
        applyBLEKeyInfoToDashboard(markAsCached: true)
    }

    func applyBLEKeyInfoToDashboard(markAsCached: Bool) {
        guard !latestBleKeyInfo.isEmpty else { return }
        var dash = dashboard
        let info = latestBleKeyInfo

        dash.bleMacText = info["bleMac"] ?? info["macAddress"] ?? dash.bleMacText
        dash.keyIdText = info["keyId"] ?? dash.keyIdText
        dash.keyTypeText = info["keyType"] ?? dash.keyTypeText
        dash.masterKeyMaskedText = maskHex(info["masterKey"], visiblePrefix: 4, visibleSuffix: 4)
        dash.randomMaskedText = maskHex(info["keyMasterRandom"] ?? info["random"], visiblePrefix: 4, visibleSuffix: 4)
        dash.keyExpiryText = info["expiredTime"] ?? info["expireTime"] ?? info["endTime"] ?? dash.keyExpiryText

        let vin = credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = credentialsStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if dash.vinText == "--", !vin.isEmpty {
            dash.vinText = vin
        }
        if dash.userIdText == "--", !phone.isEmpty {
            dash.userIdText = phone
        }

        if markAsCached {
            let current = dash.vehicleInfoUpdatedAtText.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || current == "--" {
                dash.vehicleInfoUpdatedAtText = "本地缓存"
            } else if !current.contains("缓存") {
                dash.vehicleInfoUpdatedAtText = "\(current) · 缓存"
            }
        } else {
            dash.vehicleInfoUpdatedAtText = formatDateTime(Date())
        }

        applyDashboard(dash)
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
                self.applyBLEKeyInfoToDashboard(markAsCached: false)
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

    var bleDiagnosticCountsSummaryText: String {
        "未发现 \(bleDiagnosticNoDeviceCount) · 未连上 \(bleDiagnosticFoundButNotConnectedCount) · 鉴权失败 \(bleDiagnosticAuthFailedCount)"
    }

    var bleDiagnosticCurrentCandidateText: String {
        let name = bleCurrentCandidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty || name == "--" ? deviceDisplayName : name
        if let rssi = bleCurrentCandidateRSSI {
            return "\(label) · RSSI \(rssi)"
        }
        return label
    }

    func resetBLEDiagnosticCycle() {
        bleDidSeeDeviceThisCycle = false
        bleDidReachConnectedThisCycle = false
        bleCurrentCandidateName = "--"
        bleCurrentCandidateRSSI = nil
    }

    func setBLEDiagnosticPhase(_ phase: String, detail: String) {
        bleDiagnosticPhaseText = phase
        bleDiagnosticDetailText = detail
    }

    func setBLEDiagnosticConclusion(_ conclusion: String) {
        bleDiagnosticLastConclusionText = conclusion
        bleDiagnosticLastConclusionAtText = formatTime(Date())
    }

    func noteBLEDeviceSeen(name: String, rssi: Int?) {
        bleDidSeeDeviceThisCycle = true
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty, normalized != "--" {
            bleCurrentCandidateName = normalized
        }
        if let rssi {
            bleCurrentCandidateRSSI = rssi
        }
        setBLEDiagnosticPhase("发现设备", detail: bleDiagnosticCurrentCandidateText)
    }

    func noteBLEConnectedCandidate(name: String) {
        bleDidReachConnectedThisCycle = true
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty, normalized != "--" {
            bleCurrentCandidateName = normalized
        }
        setBLEDiagnosticPhase("已连上", detail: bleDiagnosticCurrentCandidateText)
    }

    func noteBLENoDeviceFound(duration: String) {
        bleDiagnosticNoDeviceCount += 1
        let detail = "\(deviceDisplayName) · 已扫描 \(duration)"
        setBLEDiagnosticPhase("未发现设备", detail: detail)
        setBLEDiagnosticConclusion("完全没发现设备")
    }

    func noteBLEFoundButNotConnected(_ detail: String) {
        bleDiagnosticFoundButNotConnectedCount += 1
        setBLEDiagnosticPhase("发现未连上", detail: detail)
        setBLEDiagnosticConclusion("发现过设备但没连上")
    }

    func noteBLEAuthFailed(_ reason: String) {
        bleDiagnosticAuthFailedCount += 1
        setBLEDiagnosticPhase("鉴权失败", detail: reason)
        setBLEDiagnosticConclusion("连上了但鉴权失败")
    }

    func toggleBLEScanning() {
        let isActive = bleStatus == .scanning || bleStatus == .connecting || bleStatus == .authenticating || bleStatus == .authenticated
        if isActive {
            userManuallyStoppedBLE = true
            bleStatus = .disconnected
            setBLEDiagnosticPhase("手动停止", detail: "用户取消扫描")
            bleManager.stop()
            vehicleEventLogStore.add(.action, "BLE 手动停止", detail: "用户取消扫描")
        } else {
            consecutiveScanTimeouts = 0
            userManuallyStoppedBLE = false
            resetBLEDiagnosticCycle()
            setBLEDiagnosticPhase("准备扫描", detail: deviceDisplayName)
            ensureBLESession(forceRestart: true, optimisticScanning: true)
            vehicleEventLogStore.add(.action, "BLE 手动扫描", detail: "用户触发扫描")
        }
    }
}
