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

    func refreshNow() {
        lastMQTTUpdate = nil
        startHTTPPolling(immediate: true)
        fetchBleKeyInfo()
        if mqttStatus != .connected {
            reconnect()
        }
    }

    func reconnect() {
        mqtt?.disconnect()
        mqtt = nil
        credentials = nil
        lastMqttFields.removeAll()
        lastMQTTUpdate = nil
        start(with: credentialsStore)
    }
}
