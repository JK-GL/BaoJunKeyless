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

    /// - force=false：本地材料可用则永不自动打 ble/key/query（钥匙一般不过期）
    /// - force=true：仅用户手动“拉取钥匙”时强制网络刷新
    func fetchBleKeyInfo(force: Bool = false, completion: ((Bool, String) -> Void)? = nil) {
        let store = credentialsStore
        // 先尽量用本地缓存补齐，避免无意义网络
        if latestBleKeyInfo.isEmpty || !hasUsableBLEKeyInfo {
            reloadCachedBLEKeyInfo(preferScoped: true)
        }

        guard !store.accessToken.isEmpty, !store.vin.isEmpty, !store.phone.isEmpty else {
            if hasUsableBLEKeyInfo {
                refreshBLESessionIfNeeded()
                let message = "凭证不完整，已使用本地钥匙缓存"
                vehicleEventLogStore.addThrottled(.warning, "钥匙拉取跳过", detail: message, identity: "ble-key-skip", minimumInterval: 10)
                completion?(true, message)
            } else if !latestBleKeyInfo.isEmpty {
                refreshBLESessionIfNeeded()
                let message = "凭证不完整，本地钥匙字段不完整"
                vehicleEventLogStore.addThrottled(.warning, "钥匙拉取跳过", detail: message, identity: "ble-key-skip-partial", minimumInterval: 10)
                completion?(false, message)
            } else {
                let message = "无法拉取钥匙：Token / VIN / 手机号不完整"
                vehicleEventLogStore.add(.error, "钥匙拉取失败", detail: message)
                completion?(false, message)
            }
            return
        }

        // S1：本地可用就不自动拉网；仅 force（手动拉取）才刷新
        if hasUsableBLEKeyInfo && !force {
            if isFetchingBleKeyInfo {
                completion?(true, "钥匙拉取进行中，已有本地材料")
                return
            }
            refreshBLESessionIfNeeded()
            let message = "本地钥匙材料可用，跳过网络拉取"
            vehicleEventLogStore.addThrottled(.action, "钥匙拉取跳过", detail: message, identity: "ble-key-local-usable", minimumInterval: 60)
            completion?(true, message)
            return
        }

        if isFetchingBleKeyInfo {
            completion?(false, "钥匙拉取进行中")
            return
        }

        isFetchingBleKeyInfo = true
        lastBleKeyFetchAttemptAt = Date()
        vehicleEventLogStore.add(.action, "钥匙拉取开始", detail: "正在请求 ble/key/query")
        SGMWApiClient.shared.queryBleKeyResult(accessToken: store.accessToken, vin: store.vin, phone: store.phone) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isFetchingBleKeyInfo = false
                switch result {
                case .success(let info):
                    self.persistBLEKeyInfo(info)
                    self.latestBleKeyInfo = info
                    self.lastBleKeyFetchAttemptAt = Date()
                    self.refreshBLESessionIfNeeded()
                    self.applyBLEKeyInfoToDashboard(markAsCached: false)
                    let keyId = info["keyId"] ?? "--"
                    let mac = info["bleMac"] ?? info["macAddress"] ?? "--"
                    let message = "钥匙已更新 · keyId=\(keyId) · mac=\(mac)"
                    self.vehicleEventLogStore.add(.action, "钥匙拉取成功", detail: message)
                    completion?(true, message)

                case .failure(let error):
                    self.reloadCachedBLEKeyInfo(preferScoped: true)
                    if !self.latestBleKeyInfo.isEmpty {
                        // 缓存可用：拉长冷却，避免离线时每几秒刷失败日志
                        self.lastBleKeyFetchAttemptAt = Date()
                        self.refreshBLESessionIfNeeded()
                        let message = "钥匙拉取失败，已使用本地缓存：\(error.localizedDescription)"
                        self.vehicleEventLogStore.addThrottled(.warning, "钥匙拉取失败", detail: message, identity: "ble-key-fail-cache", minimumInterval: 20)
                        completion?(false, message)
                    } else {
                        let message = "钥匙拉取失败：\(error.localizedDescription)"
                        self.vehicleEventLogStore.add(.error, "钥匙拉取失败", detail: message)
                        completion?(false, message)
                    }
                }
            }
        }
    }

    func seedPreviewBLERSSI(_ rssi: Int?, reason: String = "preview") {
        guard let rssi else { return }
        // 仅写诊断显示域，不走 apply(state) / 靠近语义，避免连接前误触发无感
        debugBLERawRSSI = rssi
        debugBLESmoothedRSSI = rssi
        bleDiagnosticsStore.isPreviewRSSI = true
        debugBLELastSeenText = formatTime(Date())
        vehicleEventLogStore.addThrottled(
            .ble,
            "RSSI预填",
            detail: "\(reason)=\(rssi) dBm（连接中广播值，鉴权后切 live）",
            identity: "rssi-preview|\(reason)",
            minimumInterval: 3
        )
    }

    func seedPreviewBLERSSIFromNearbyIfPossible() {
        // bound 直连时可能没有刚扫到的 candidate RSSI，回退附近列表同 UUID
        if let boundId = VehicleBLEBindingStore.load()?.peripheralIdentifier,
           let device = nearbyBLEDevicesStore.devices.first(where: { $0.peripheralIdentifier == boundId }) {
            noteBLEDeviceSeen(name: device.displayName, rssi: device.rssi)
            seedPreviewBLERSSI(device.rssi, reason: "nearby-bound")
            return
        }
        if let best = nearbyBLEDevicesStore.devices.first(where: { $0.exactMatched })
            ?? nearbyBLEDevicesStore.devices.max(by: { $0.rssi < $1.rssi }),
           best.exactMatched {
            noteBLEDeviceSeen(name: best.displayName, rssi: best.rssi)
            seedPreviewBLERSSI(best.rssi, reason: "nearby-exact")
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
        bleDiagnosticsStore.countsSummaryText
    }

    var bleDiagnosticCurrentCandidateText: String {
        bleDiagnosticsStore.currentCandidateText(fallbackName: deviceDisplayName)
    }

    func resetBLEDiagnosticCycle() {
        bleDiagnosticsStore.resetCycle()
    }

    func resetNearbyBLEDevices() {
        nearbyBLEDevicesStore.reset()
    }

    func handleNearbyBLEDeviceDiscovered(_ device: VehicleBLEManager.NearbyDevice) {
        nearbyBLEDevicesStore.ingest(device)
    }

    func flushNearbyBLEDevices() {
        nearbyBLEDevicesStore.flush()
    }

    func bindNearbyBLEDevice(_ device: VehicleBLEManager.NearbyDevice) {
        let keyId = latestBleKeyInfo["keyId"] ?? ""
        let mac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? device.manufacturerMac ?? ""
        let binding = VehicleBLEBinding(
            peripheralIdentifier: device.peripheralIdentifier,
            peripheralName: device.displayName,
            keyId: keyId,
            bleMacSuffix: mac,
            boundAt: Date(),
            lastAuthAt: Date()
        )
        VehicleBLEBindingStore.save(binding)

        // 先预填广播 RSSI，再重启会话，避免 stop/idle 把预填冲掉
        userManuallyStoppedBLE = false
        noteBLEDeviceSeen(name: device.displayName, rssi: device.rssi)
        seedPreviewBLERSSI(device.rssi, reason: "bind-ad")
        setBLEDiagnosticPhase("连接中", detail: "绑定优先 · \(device.displayName) · \(device.rssi) dBm")
        bleStatus = .connecting
        vehicleEventLogStore.add(
            .action,
            "手动绑定蓝牙设备",
            detail: "\(binding.displaySummary) · 正在优先连接 · adRSSI=\(device.rssi)"
        )

        ignoreNextBLEIdleCallback = true
        bleManager.stop()
        // stop 后再次保住预填，防止 idle 清空
        seedPreviewBLERSSI(device.rssi, reason: "bind-ad-keep")
        bleStatus = .connecting
        refreshBLESessionIfNeeded()
        if !hasUsableBLEKeyInfo {
            fetchBleKeyInfo(force: false)
        }
    }

    func clearBLEBindingAndRefresh() {
        VehicleBLEBindingStore.clear()
        ensureBLESession(forceRestart: true, optimisticScanning: true, userInitiated: true)
        vehicleEventLogStore.add(.action, "清除蓝牙绑定", detail: "用户手动取消绑定")
    }

    func setBLEDiagnosticPhase(_ phase: String, detail: String) {
        bleDiagnosticsStore.setPhase(phase, detail: detail)
    }

    func setBLEDiagnosticConclusion(_ conclusion: String, reason: String = "--") {
        bleDiagnosticsStore.setConclusion(conclusion, reason: reason)
    }

    func noteBLEDeviceSeen(name: String, rssi: Int?) {
        bleDiagnosticsStore.noteDeviceSeen(name: name, rssi: rssi, fallbackName: deviceDisplayName)
    }

    func noteBLEConnectedCandidate(name: String) {
        bleDiagnosticsStore.noteConnectedCandidate(name: name, fallbackName: deviceDisplayName)
    }

    func noteBLENoDeviceFound(duration: String) {
        bleDiagnosticsStore.noteNoDeviceFound(displayName: deviceDisplayName, duration: duration)
    }

    func noteBLEFoundButNotConnected(_ detail: String, reason: String = "已发现目标，但连接未完成") {
        bleDiagnosticsStore.noteFoundButNotConnected(detail, reason: reason)
    }

    func noteBLEAuthFailed(_ reason: String) {
        bleDiagnosticsStore.noteAuthFailed(reason)
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
            ensureBLESession(forceRestart: true, optimisticScanning: true, userInitiated: true)
            vehicleEventLogStore.add(.action, "BLE 手动扫描", detail: "用户触发扫描")
        }
    }
}
