import Foundation

extension MQTTVehicleStateStore {
    func autoConnect() {
        userManuallyStoppedBLE = false
        if keylessSettingsStore.settings.keylessEnabled || AppDiagnosticsSettings.vehicleControlRouteMode == .forceBLE {
            ensureBLESession(forceRestart: false, optimisticScanning: true)
        }

        let saved = credentialsStore
        if saved.isConfigured {
            start(with: saved)
            return
        }

        guard let tokenInfo = SGMWApiClient.shared.readLocalTokenInfo() else {
            mqttStatus = .disconnected
            if case .expired("缓存模式") = authStatus {
                // 无 token 走缓存是预期路径，不写错误日志
            } else {
                authStatus = .expired("未读取到Token")
                // 无 token：用户可见层处理，不写错误日志
            }
            return
        }

        let token = tokenInfo.token
        updateTokenSource(label: "五菱 App 自动读取", path: tokenInfo.sourcePath)
        applyCachedSnapshotIfAvailable()

        authStatus = .valid
        SGMWApiClient.shared.queryDefaultCarResult(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    let store = VehicleCredentialsStore.shared
                    store.accessToken = token
                    store.vin = info.vin
                    store.phone = info.phone
                    store.tokenSourceLabel = "五菱 App 自动读取"
                    store.tokenSourcePath = tokenInfo.sourcePath
                    self.start(with: store)
                case .failure(let error):
                    self.authStatus = .expired("车辆查询失败：\(error.localizedDescription)")
                    CrashLogger.shared.mark("HTTP", "queryDefaultCar failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func start(with credentialsStore: VehicleCredentialsStore) {
        self.credentialsStore = credentialsStore
        reloadCachedBLEKeyInfo(preferScoped: true)
        updateTokenSource(label: inferredTokenSourceLabel(from: credentialsStore), path: credentialsStore.tokenSourcePath)
        guard !credentialsStore.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authStatus = .expired("Token为空")
            mqttStatus = .disconnected
            return
        }
        guard !credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            authStatus = .expired("VIN为空")
            mqttStatus = .disconnected
            return
        }

        authStatus = .valid
        startHTTPPolling(immediate: true)
        fetchBleKeyInfo(force: false)
        startMQTTIfEnabled()
    }

    /// MQTT 为可选增强通道：只在设置开启且尚未连接时获取凭证并连接。
    func startMQTTIfEnabled() {
        guard keylessSettingsStore.settings.mqttEnabled else {
            stopMQTTForSettingsChange(logEvent: false)
            return
        }
        guard credentialsStore.isConfigured else {
            mqttStatus = .disconnected
            return
        }
        guard mqttStatus != .connected, mqttStatus != .connecting, !isConnecting else { return }

        isConnecting = true
        mqttConnectionGeneration &+= 1
        let generation = mqttConnectionGeneration
        mqttStatus = .connecting
        SGMWApiClient.shared.fetchMqttTokenResult(
            accessToken: credentialsStore.accessToken,
            vin: credentialsStore.vin
        ) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard generation == self.mqttConnectionGeneration else { return }
                self.isConnecting = false
                guard self.keylessSettingsStore.settings.mqttEnabled else {
                    self.stopMQTTForSettingsChange(logEvent: false)
                    return
                }
                switch result {
                case .success(let mqttToken):
                    let creds = SGMWApiClient.shared.generateMQTTCredentials(
                        vin: self.credentialsStore.vin,
                        phone: self.credentialsStore.phone,
                        mqttToken: mqttToken
                    )
                    self.credentials = creds
                    self.connectMQTT(creds)
                case .failure(let error):
                    self.mqttStatus = .error
                    CrashLogger.shared.mark("MQTT", "mqtt token fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 设置关闭 MQTT 时仅停可选通道，不清 HTTP/BLE 状态。
    func stopMQTTForSettingsChange(logEvent: Bool = true) {
        mqttConnectionGeneration &+= 1
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
        credentials = nil
        isConnecting = false
        lastMqttFields.removeAll()
        lastMQTTUpdate = nil
        lastMQTTBodyCollectAt = nil
        mqttStatus = .disconnected
        if logEvent {
            vehicleEventLogStore.add(.system, "MQTT 已停用", detail: "HTTP 完整车况继续运行")
        }
    }

    /// 协议兼容入口：命令执行后静默刷新，不弹手动结果 Toast。
    func refreshNow() {
        refreshNow(userInitiated: false, completion: nil)
    }

    /// 手动刷新：车况 + 钥匙 + 必要时 MQTT 重连。
    /// completion 汇总给 UI Toast 用。
    func refreshNow(userInitiated: Bool, completion: ((Bool, String) -> Void)? = nil) {
        lastMQTTUpdate = nil

        if userInitiated {
            vehicleEventLogStore.add(.action, "手动刷新开始", detail: "车况 + 钥匙 + MQTT 状态")
        }

        let group = DispatchGroup()
        var statusOK = false
        var statusMessage = "车况未刷新"
        var keyOK = false
        var keyMessage = "钥匙未刷新"
        var mqttNote: String?

        group.enter()
        pollHTTPOnce(userInitiated: userInitiated) { ok, message in
            statusOK = ok
            statusMessage = message
            group.leave()
        }

        group.enter()
        fetchBleKeyInfo(force: false) { ok, message in
            keyOK = ok
            keyMessage = message
            group.leave()
        }

        if keylessSettingsStore.settings.mqttEnabled {
            if mqttStatus != .connected {
                mqttNote = "MQTT 未连接，正在重连"
                if userInitiated {
                    vehicleEventLogStore.add(.action, "MQTT 重连开始", detail: mqttNote ?? "")
                }
                reconnect()
            } else if userInitiated {
                mqttNote = "MQTT 已连接"
            }
        } else if userInitiated {
            mqttNote = "MQTT 已关闭"
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let ok = statusOK || keyOK
            var parts: [String] = []
            parts.append(statusOK ? "车况成功" : "车况失败")
            parts.append(keyOK ? "钥匙成功" : "钥匙失败")
            if let mqttNote { parts.append(mqttNote) }

            let summary = parts.joined(separator: " · ")
            let detail = "\(statusMessage)；\(keyMessage)" + (mqttNote.map { "；\($0)" } ?? "")
            if userInitiated {
                self.vehicleEventLogStore.add(ok ? .action : .warning, "手动刷新结果", detail: detail)
            }
            completion?(ok, summary)
        }
    }

    func reconnect(userInitiated: Bool = false, completion: ((Bool, String) -> Void)? = nil) {
        guard keylessSettingsStore.settings.mqttEnabled else {
            stopMQTTForSettingsChange(logEvent: false)
            completion?(false, "MQTT 已在设置中关闭")
            return
        }
        if userInitiated {
            vehicleEventLogStore.add(.action, "MQTT 重连开始", detail: "断开后重新获取 mqtt token")
        }
        mqttConnectionGeneration &+= 1
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
        mqtt = nil
        credentials = nil
        isConnecting = false
        lastMqttFields.removeAll()
        lastMQTTUpdate = nil
        lastMQTTBodyCollectAt = nil
        mqttStatus = .disconnected

        // 仅重启 MQTT；HTTP 权威状态、BLE 本地锁保护和状态版本保持不动。
        startMQTTIfEnabled()

        // 给 UI 一个短等待结果：连接成功 / 失败 / 超时
        let startedAt = Date()
        func pollResult(attempt: Int) {
            if self.mqttStatus == .connected {
                let message = "MQTT 已连接"
                if userInitiated {
                    self.vehicleEventLogStore.add(.action, "MQTT 重连成功", detail: message)
                }
                completion?(true, message)
                return
            }
            if self.mqttStatus == .error {
                let message = "MQTT 重连失败"
                if userInitiated {
                    self.vehicleEventLogStore.add(.error, "MQTT 重连失败", detail: message)
                }
                completion?(false, message)
                return
            }
            if attempt >= 16 { // ~8s
                let message = "MQTT 重连超时，请稍后查看状态"
                if userInitiated {
                    self.vehicleEventLogStore.add(.warning, "MQTT 重连超时", detail: "waited=\(Int(Date().timeIntervalSince(startedAt)))s")
                }
                completion?(false, message)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pollResult(attempt: attempt + 1)
            }
        }
        if completion != nil || userInitiated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pollResult(attempt: 0)
            }
        }
    }
}
