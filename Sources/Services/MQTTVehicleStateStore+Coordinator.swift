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
                CrashLogger.shared.mark("MQTT", "no local token found, keep cache mode")
            } else {
                authStatus = .expired("未读取到Token")
                CrashLogger.shared.mark("MQTT", "no local token found")
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
        guard !isConnecting else { return }
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

        isConnecting = true
        authStatus = .valid
        mqttStatus = .connecting

        startHTTPPolling(immediate: true)
        fetchBleKeyInfo()

        SGMWApiClient.shared.fetchMqttTokenResult(accessToken: credentialsStore.accessToken, vin: credentialsStore.vin) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isConnecting = false
                switch result {
                case .success(let mqttToken):
                    let creds = SGMWApiClient.shared.generateMQTTCredentials(vin: credentialsStore.vin, phone: credentialsStore.phone, mqttToken: mqttToken)
                    self.credentials = creds
                    self.connectMQTT(creds)
                case .failure(let error):
                    self.mqttStatus = .error
                    CrashLogger.shared.mark("MQTT", "mqtt token fetch failed: \(error.localizedDescription)")
                }
            }
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
        fetchBleKeyInfo { ok, message in
            keyOK = ok
            keyMessage = message
            group.leave()
        }

        if mqttStatus != .connected {
            mqttNote = "MQTT 未连接，正在重连"
            if userInitiated {
                vehicleEventLogStore.add(.action, "MQTT 重连开始", detail: mqttNote ?? "")
            }
            reconnect()
        } else if userInitiated {
            mqttNote = "MQTT 已连接"
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
        if userInitiated {
            vehicleEventLogStore.add(.action, "MQTT 重连开始", detail: "断开后重新获取 mqtt token")
        }
        mqtt?.disconnect()
        mqtt = nil
        credentials = nil
        lastMqttFields.removeAll()
        lastMQTTUpdate = nil
        lastMQTTBodyCollectAt = nil
        lastHTTPBodyCollectAt = nil
        fieldCollectAt.removeAll()

        // 复用 start；用一次性观察给出结果提示
        start(with: credentialsStore)

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
