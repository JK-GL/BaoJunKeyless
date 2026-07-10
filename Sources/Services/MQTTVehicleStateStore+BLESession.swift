import Foundation
import UIKit
import Combine

extension MQTTVehicleStateStore {
    func setupBLECallbacks() {
        bleManager.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                if self.ignoreNextBLEIdleCallback {
                    self.ignoreNextBLEIdleCallback = false
                    return
                }
                switch self.bleManager.state {
                case .scanning, .connecting, .connected, .authenticating, .authenticated:
                    return
                default:
                    break
                }
                let macSuffix = self.deviceDisplayName
                if self.bleStatus == .scanning {
                    self.consecutiveScanTimeouts += 1
                    let duration = self.formatElapsedSince(self.bleScanStartedAt ?? Date())
                    if self.bleDidSeeDeviceThisCycle {
                        self.vehicleEventLogStore.addCoalesced(.warning, "BLE 扫描结束", detail: "\(self.bleDiagnosticCurrentCandidateText) · 已扫描 \(duration)，发现设备但未连上", identity: "scan-end-seen|\(macSuffix)")
                        self.noteBLEFoundButNotConnected("\(self.bleDiagnosticCurrentCandidateText) · 已扫描 \(duration)", reason: "看到目标设备，但本轮未建立连接")
                    } else {
                        self.vehicleEventLogStore.addCoalesced(.action, "BLE 扫描超时", detail: "\(macSuffix) · 已扫描 \(duration)，未发现设备", identity: "scan-timeout|\(macSuffix)")
                        self.noteBLENoDeviceFound(duration: duration)
                    }
                    self.resetBLEDiagnosticCycle()
                } else if self.bleStatus == .connecting || self.bleStatus == .authenticating || self.bleStatus == .authenticated {
                    let duration = self.formatElapsedSince(self.bleScanStartedAt ?? Date())
                    self.logVehicleEvent(.action, "BLE 已断开", detail: "\(macSuffix) · 扫描耗时 \(duration)", identity: "disconnect|\(macSuffix)", minimumInterval: 4)
                    self.setBLEDiagnosticPhase("已断开", detail: "\(macSuffix) · 扫描耗时 \(duration)")
                    self.resetBLEDiagnosticCycle()
                }
                self.bleStatus = .disconnected
                self.bleScanStartedAt = nil
                self.hasCompletedBLEAuth = false
                self.applyLiveBLERSSI(nil)
            case .unsupported, .bluetoothOff:
                self.ignoreNextBLEIdleCallback = false
                self.bleStatus = .error
                self.bleScanStartedAt = nil
                self.hasCompletedBLEAuth = false
                self.applyLiveBLERSSI(nil)
                self.setBLEDiagnosticPhase("BLE不可用", detail: "蓝牙关闭或未授权")
                self.setBLEDiagnosticConclusion("BLE 不可用", reason: "系统蓝牙关闭或权限不可用")
                self.logVehicleEvent(.action, "BLE 不可用", detail: "蓝牙关闭或未授权", identity: "ble-unavailable", minimumInterval: 8)
            case .scanning:
                self.ignoreNextBLEIdleCallback = false
                if self.bleScanStartedAt == nil {
                    self.bleScanStartedAt = Date()
                    self.resetBLEDiagnosticCycle()
                }
                if self.bleStatus != .scanning {
                    let timeout = Int(self.keylessSettingsStore.settings.bleScanDuration)
                    let interval = Int(self.effectiveScanRetryInterval(baseInterval: self.keylessSettingsStore.settings.bleScanInterval))
                    let intervalText = interval <= 0 ? "无间隙" : "间隔 \(interval)s"
                    let macSuffix = self.deviceDisplayName
                    self.vehicleEventLogStore.addCoalesced(.action, "BLE 扫描中", detail: "\(macSuffix) · 最长 \(timeout)s · \(intervalText)", identity: "scan-start|\(macSuffix)")
                    self.setBLEDiagnosticPhase("扫描中", detail: "\(macSuffix) · 最长 \(timeout)s · \(intervalText)")
                }
                self.bleStatus = .scanning
            case .connecting:
                self.ignoreNextBLEIdleCallback = false
                self.consecutiveScanTimeouts = 0
                self.setBLEDiagnosticPhase("连接中", detail: self.bleDiagnosticCurrentCandidateText)
                // 连接中先用扫描阶段拿到的广播 RSSI 预填，避免雷达先显示 -- dBm
                if let adRSSI = self.bleCurrentCandidateRSSI {
                    self.seedPreviewBLERSSI(adRSSI, reason: "scan-ad")
                } else {
                    self.seedPreviewBLERSSIFromNearbyIfPossible()
                }
                self.bleStatus = .connecting
            case .connected:
                self.ignoreNextBLEIdleCallback = false
                self.consecutiveScanTimeouts = 0
                let macSuffix = self.deviceDisplayName
                self.logVehicleEvent(.action, "BLE 已连接", detail: "\(macSuffix) · 开始鉴权", identity: "connecting|\(macSuffix)", minimumInterval: 3)
                self.setBLEDiagnosticPhase("鉴权中", detail: self.bleDiagnosticCurrentCandidateText)
                if let adRSSI = self.bleCurrentCandidateRSSI {
                    self.seedPreviewBLERSSI(adRSSI, reason: "connected-ad")
                }
                self.bleStatus = .authenticating
            case .authenticating:
                self.ignoreNextBLEIdleCallback = false
                self.logVehicleEvent(.action, "BLE 鉴权中", detail: "38C7/A857 四步鉴权", identity: "authenticating", minimumInterval: 3)
                self.setBLEDiagnosticPhase("鉴权中", detail: self.bleDiagnosticCurrentCandidateText)
                if let adRSSI = self.bleCurrentCandidateRSSI {
                    self.seedPreviewBLERSSI(adRSSI, reason: "auth-ad")
                }
                self.bleStatus = .authenticating
            case .authenticated:
                self.ignoreNextBLEIdleCallback = false
                self.consecutiveScanTimeouts = 0
                self.hasCompletedBLEAuth = true
                self.setBLEDiagnosticPhase("已鉴权", detail: self.bleDiagnosticCurrentCandidateText)
                self.setBLEDiagnosticConclusion("鉴权成功", reason: "已完成 BLE 四步鉴权")
                self.logVehicleEvent(.action, "BLE 鉴权成功", detail: "可发送控车命令", identity: "authenticated", minimumInterval: 3)
                self.bleStatus = .authenticated
            case .authFailed(let reason):
                self.ignoreNextBLEIdleCallback = false
                self.noteBLEAuthFailed(reason)
                self.bleScanStartedAt = nil
                self.logVehicleEvent(.error, "BLE 鉴权失败", detail: reason, identity: "auth-failed|\(reason)", minimumInterval: 6)
                self.bleStatus = .error
                self.applyLiveBLERSSI(nil)
            case .error(let detail):
                self.ignoreNextBLEIdleCallback = false
                self.bleScanStartedAt = nil
                self.logVehicleEvent(.error, "BLE 错误", detail: detail, identity: "ble-error|\(detail)", minimumInterval: 6)
                self.setBLEDiagnosticPhase("BLE错误", detail: detail)
                self.bleStatus = .error
                self.applyLiveBLERSSI(nil)
            }
        }
        bleManager.onLog = { [weak self] component, message in
            guard let self else { return }
            if let message {
                if self.shouldPersistBLECrashLog(message) {
                    CrashLogger.shared.mark(component, message)
                }
                if self.shouldHandleBLEDiagnosticLog(message) {
                    DispatchQueue.main.async {
                        self.handleBLEDiagnosticLog(message)
                    }
                }
            }
        }
        bleManager.onNearbyDeviceDiscovered = { [weak self] device in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleNearbyBLEDeviceDiscovered(device)
            }
        }
        bleManager.onControlReceipt = { [weak self] receipt in
            guard let self else { return }
            DispatchQueue.main.async {
                self.latestBLEControlReceipt = receipt
                self.vehicleEventLogStore.add(.action, "BLE 控制回包", detail: receipt.displayDetail)
            }
        }
        bleManager.onRSSIUpdate = { [weak self] rssi in
            guard let self else { return }
            DispatchQueue.main.async {
                self.applyLiveBLERSSI(rssi)
            }
        }
        bleManager.onControlCompletion = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.refreshNow()
            }
        }
    }

    func refreshBLESessionIfNeeded() {
        let settings = keylessSettingsStore.settings
        let routeMode = AppDiagnosticsSettings.vehicleControlRouteMode
        let shouldKeepBLESession = settings.keylessEnabled || routeMode == .forceBLE
        guard shouldKeepBLESession else {
            bleManager.stop()
            bleStatus = .disconnected
            return
        }
        guard !userManuallyStoppedBLE else { return }
        let bleMac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? ""
        let keyId = latestBleKeyInfo["keyId"] ?? ""
        let masterKey = latestBleKeyInfo["masterKey"] ?? ""
        let keyMasterRandom = latestBleKeyInfo["keyMasterRandom"] ?? latestBleKeyInfo["random"] ?? ""
        let controlAes128Key = latestBleKeyInfo["controlAes128Key"]
        let bleType = latestBleKeyInfo["bleType"]
        let bleKey = latestBleKeyInfo["bleKey"]
        guard !bleMac.isEmpty, !keyId.isEmpty, !masterKey.isEmpty, !keyMasterRandom.isEmpty else {
            bleManager.stop()
            bleStatus = .disconnected
            return
        }
        bleManager.scanTimeoutDuration = max(20, min(300, settings.bleScanDuration))
        bleManager.scanRetryInterval = effectiveScanRetryInterval(baseInterval: settings.bleScanInterval)
        bleManager.start(config: .init(bleMac: bleMac, keyId: keyId, masterKey: masterKey, keyMasterRandom: keyMasterRandom, controlAes128Key: controlAes128Key, bleType: bleType, bleKey: bleKey))
    }

    func ensureBLESession(forceRestart: Bool, optimisticScanning: Bool) {
        if forceRestart {
            userManuallyStoppedBLE = false
            ignoreNextBLEIdleCallback = true
            bleManager.stop()
        }
        if latestBleKeyInfo.isEmpty {
            reloadCachedBLEKeyInfo(preferScoped: true)
        }
        if optimisticScanning,
           keylessSettingsStore.settings.keylessEnabled || AppDiagnosticsSettings.vehicleControlRouteMode == .forceBLE,
           !userManuallyStoppedBLE,
           hasUsableBLEKeyInfo {
            let timeout = Int(keylessSettingsStore.settings.bleScanDuration)
            let interval = Int(effectiveScanRetryInterval(baseInterval: keylessSettingsStore.settings.bleScanInterval))
            let intervalText = interval <= 0 ? "无间隙" : "间隔 \(interval)s"
            if bleStatus != .scanning {
                vehicleEventLogStore.addCoalesced(.action, "BLE 扫描中", detail: "\(deviceDisplayName) · 最长 \(timeout)s · \(intervalText)", identity: "scan-start|\(deviceDisplayName)")
            }
            resetNearbyBLEDevices()
            setBLEDiagnosticPhase("扫描中", detail: "\(deviceDisplayName) · 最长 \(timeout)s · \(intervalText)")
            bleStatus = .scanning
        }
        refreshBLESessionIfNeeded()
        if !hasUsableBLEKeyInfo || forceRestart {
            fetchBleKeyInfo()
        }
    }

    var hasUsableBLEKeyInfo: Bool {
        let bleMac = latestBleKeyInfo["bleMac"] ?? latestBleKeyInfo["macAddress"] ?? ""
        let keyId = latestBleKeyInfo["keyId"] ?? ""
        let masterKey = latestBleKeyInfo["masterKey"] ?? ""
        let keyMasterRandom = latestBleKeyInfo["keyMasterRandom"] ?? latestBleKeyInfo["random"] ?? ""
        return !bleMac.isEmpty && !keyId.isEmpty && !masterKey.isEmpty && !keyMasterRandom.isEmpty
    }

    func setupLifecycleObservers() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isAppInForeground = true
            self.didLogManualForegroundSkip = false
            if !self.userManuallyStoppedBLE {
                self.ensureBLESession(forceRestart: false, optimisticScanning: true)
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isAppInForeground = false
            self.didLogManualForegroundSkip = false
        }
    }

    func setupRouteModeObserver() {
        routeModeObserver = NotificationCenter.default.addObserver(
            forName: .vehicleControlRouteModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.bleManager.stop()
            self.userManuallyStoppedBLE = false
            self.ensureBLESession(forceRestart: false, optimisticScanning: true)
        }
    }

    func setupKeylessSettingsObserver() {
        lastObservedKeylessEnabled = keylessSettingsStore.settings.keylessEnabled
        keylessSettingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                let isFirst = !self.hasReceivedKeylessSettings
                self.hasReceivedKeylessSettings = true
                let wasEnabled = self.lastObservedKeylessEnabled
                self.lastObservedKeylessEnabled = settings.keylessEnabled

                if isFirst {
                    self.refreshBLESessionIfNeeded()
                    return
                }

                if settings.keylessEnabled {
                    let justEnabled = wasEnabled != true
                    if justEnabled {
                        self.consecutiveScanTimeouts = 0
                        self.ensureBLESession(forceRestart: true, optimisticScanning: true)
                        self.vehicleEventLogStore.add(.action, "BLE 自动扫描", detail: "无感开关已开启")
                    } else {
                        self.refreshBLESessionIfNeeded()
                    }
                } else {
                    self.userManuallyStoppedBLE = false
                    self.bleManager.stop()
                    self.bleStatus = .disconnected
                    self.setBLEDiagnosticPhase("无感关闭", detail: "无感开关已关闭")
                    if wasEnabled != false {
                        self.resetKeylessRuntimeState()
                        self.vehicleEventLogStore.add(.action, "BLE 已停止", detail: "无感开关已关闭")
                    }
                }
            }
            .store(in: &cancellables)
    }

    func handleBLEDiagnosticLog(_ message: String) {
        if message.contains("manufacturer candidate name=") {
            guard message.contains("match=1") else { return }
            let name = nameValue(in: message) ?? "--"
            let rssi = value(in: message, key: "rssi=").flatMap(Int.init)
            noteBLEDeviceSeen(name: name, rssi: rssi)
            return
        }

        if message.contains("connecting bound peripheral") || message.contains("connecting manufacturer candidate") || message.contains("connecting debugScore candidate") {
            let name = nameValue(in: message) ?? bleCurrentCandidateName
            noteBLEDeviceSeen(name: name, rssi: bleCurrentCandidateRSSI)
            setBLEDiagnosticPhase("连接中", detail: bleDiagnosticCurrentCandidateText)
            return
        }

        if message.contains("connected ") && message.contains("discover all services") {
            let name = message
                .replacingOccurrences(of: "connected ", with: "")
                .components(separatedBy: " source=")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? bleCurrentCandidateName
            noteBLEConnectedCandidate(name: name)
            return
        }

        if message.contains("connect failed source=") {
            noteBLEFoundButNotConnected(bleDiagnosticCurrentCandidateText, reason: "连接失败")
            return
        }

        if message.contains("connection timeout (10s)") {
            noteBLEFoundButNotConnected(bleDiagnosticCurrentCandidateText, reason: "连接超时")
            return
        }

        if message.contains("target services incomplete") {
            noteBLEFoundButNotConnected(bleDiagnosticCurrentCandidateText, reason: "服务/特征不完整")
            return
        }
    }

    private func nameValue(in text: String) -> String? {
        guard let range = text.range(of: "name=") else { return nil }
        let tail = text[range.upperBound...]
        let delimiters = [" rssi=", " score=", " id=", " source=", " |"]
        let end = delimiters.compactMap { token in tail.range(of: token).map(\.lowerBound) }.min() ?? tail.endIndex
        return String(tail[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldPersistBLECrashLog(_ message: String) -> Bool {
        if message.contains("manufacturer candidate name=") { return false }
        if message.contains("debug score candidate name=") { return false }
        if message.hasPrefix("rssi=") { return false }
        if message.contains("notify uuid=") { return false }
        return true
    }

    private func shouldHandleBLEDiagnosticLog(_ message: String) -> Bool {
        if message.contains("manufacturer candidate name=") { return true }
        if message.contains("connecting bound peripheral") { return true }
        if message.contains("connecting manufacturer candidate") { return true }
        if message.contains("connecting debugScore candidate") { return true }
        if message.contains("connected ") && message.contains("discover all services") { return true }
        if message.contains("connect failed source=") { return true }
        if message.contains("connection timeout (10s)") { return true }
        if message.contains("target services incomplete") { return true }
        return false
    }

    private func value(in text: String, key: String) -> String? {
        guard let range = text.range(of: key) else { return nil }
        let tail = text[range.upperBound...]
        let raw = tail.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? String(tail)
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "|,"))
    }

    func effectiveScanRetryInterval(baseInterval: TimeInterval) -> TimeInterval {
        max(0, min(300, baseInterval))
    }
}
