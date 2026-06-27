import Foundation
import CocoaMQTT

// MARK: - MQTT + HTTP 车辆状态 Store
// 双通道：
// - HTTP：电量/续航/位置/档位/温度等基础状态（稳定兜底）
// - MQTT：门锁/车窗/空调/控制结果等实时变化
// 控制和无感暂不接入真实执行

final class MQTTVehicleStateStore: VehicleStateStore {

    // MARK: - 连接状态

    enum LiveBLEStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error
    }

    enum LiveMQTTStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error
    }

    @Published private(set) var bleStatus: LiveBLEStatus = .disconnected
    @Published private(set) var mqttStatus: LiveMQTTStatus = .disconnected
    @Published private(set) var authStatus: StatusAuthState = .expired("未登录")
    @Published private(set) var latestLatitude: Double = 0
    @Published private(set) var latestLongitude: Double = 0
    @Published private(set) var latestAddress: String = ""
    @Published private(set) var shouldPreferCachedAddress: Bool = false
    @Published private(set) var latestBleKeyInfo: [String: String] = [:]
    @Published private(set) var tokenSourcePath: String = ""

    private var mqtt: CocoaMQTT?
    private var credentials: SGMWApiClient.MQTTCredentials?
    private var credentialsStore: VehicleCredentialsStore?

    private var lastMqttFields: [String: String] = [:]
    private var httpTimer: Timer?
    private var lastMQTTUpdate: Date?
    private var lastHTTPUpdate: Date?
    private var isConnecting = false

    private let locationResolver = LocationResolver.shared

    init() {
        super.init(state: .placeholder, dashboard: VehicleDashboardState())
        applyCachedSnapshotIfAvailable()
        DispatchQueue.main.async { [weak self] in
            self?.autoConnect()
        }
    }

    deinit {
        httpTimer?.invalidate()
        mqtt?.disconnect()
    }

    // MARK: - 启动 / 重连

    private func applyCachedSnapshotIfAvailable() {
        guard let snapshot = WulingAppCacheReader.shared.readStatusCache() else { return }

        var cachedState = mapHTTPToVehicleState(snapshot.carStatus)
        cachedState.timestamp = Date()
        var cachedDashboard = mapHTTPToDashboard(snapshot.carStatus)
        cachedDashboard.updatedAt = Date()
        cachedDashboard.updatedAtText = formatTime(Date())

        if let gcjLat = snapshot.latitude, let gcjLng = snapshot.longitude, gcjLat != 0, gcjLng != 0 {
            let wgs = LocationResolver.gcj02ToWgs84Approx(lat: gcjLat, lng: gcjLng)
            latestLatitude = wgs.lat
            latestLongitude = wgs.lng
        }

        if let address = snapshot.address, !address.isEmpty {
            latestAddress = address
            shouldPreferCachedAddress = true
            UserDefaults.standard.set(address, forKey: "LastAddress")
        }

        apply(cachedState)
        applyDashboard(cachedDashboard)
        authStatus = .expired("缓存模式")
        CrashLogger.shared.mark("CACHE", "loaded Wuling cache from \(snapshot.sourcePath)")
    }

    private func autoConnect() {
        let saved = VehicleCredentialsStore()
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
        tokenSourcePath = tokenInfo.sourcePath

        authStatus = .valid
        SGMWApiClient.shared.queryDefaultCar(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let result else {
                    self.authStatus = .expired("车辆查询失败")
                    CrashLogger.shared.mark("HTTP", "queryDefaultCar failed")
                    return
                }
                let store = VehicleCredentialsStore()
                store.accessToken = token
                store.vin = result.vin
                store.phone = result.phone
                self.start(with: store)
            }
        }
    }

    func start(with credentialsStore: VehicleCredentialsStore) {
        self.credentialsStore = credentialsStore
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

        // 先走 HTTP，拿到基础状态/经纬度/电量等
        startHTTPPolling(immediate: true)
        fetchBleKeyInfo()

        SGMWApiClient.shared.fetchMqttToken(accessToken: credentialsStore.accessToken, vin: credentialsStore.vin) { [weak self] mqttToken in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isConnecting = false
                guard let mqttToken, !mqttToken.isEmpty else {
                    self.mqttStatus = .error
                    CrashLogger.shared.mark("MQTT", "mqtt token fetch failed")
                    return
                }
                let creds = SGMWApiClient.shared.generateMQTTCredentials(vin: credentialsStore.vin, phone: credentialsStore.phone, mqttToken: mqttToken)
                self.credentials = creds
                self.connectMQTT(creds)
            }
        }
    }

    func reconnect() {
        mqtt?.disconnect()
        mqtt = nil
        credentials = nil
        lastMqttFields.removeAll()
        lastMQTTUpdate = nil
        if let store = credentialsStore {
            start(with: store)
        }
    }

    // MARK: - HTTP 轮询

    private func startHTTPPolling(immediate: Bool) {
        httpTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollHTTPOnce()
        }
        httpTimer = timer
        if immediate { pollHTTPOnce() }
    }

    private func pollHTTPOnce() {
        guard let store = credentialsStore else { return }
        let token = store.accessToken
        guard !token.isEmpty else { return }

        SGMWApiClient.shared.queryVehicleStatus(accessToken: token) { [weak self] payload in
            guard let self, let payload else { return }
            DispatchQueue.main.async {
                self.lastHTTPUpdate = Date()
                let newState = self.mapHTTPToVehicleState(payload.carStatus)
                let newDashboard = self.mapHTTPToDashboard(payload.carStatus)
                let shouldUseHTTP = self.lastMQTTUpdate == nil || Date().timeIntervalSince(self.lastMQTTUpdate!) >= 60

                // 基础状态永远以 HTTP 回填（特别是经纬度/电量/续航/档位）
                self.mergeHTTPBaseState(newState: newState, dashboard: newDashboard)

                if shouldUseHTTP {
                    self.apply(newState)
                    self.applyDashboard(newDashboard)
                }

                self.applyHTTPMeta(carInfo: payload.carInfo, carStatus: payload.carStatus)
                CrashLogger.shared.mark("HTTP", "status updated")
            }
        }
    }

    private func fetchBleKeyInfo() {
        guard let store = credentialsStore else { return }
        guard !store.accessToken.isEmpty, !store.vin.isEmpty, !store.phone.isEmpty else { return }
        SGMWApiClient.shared.queryBleKey(accessToken: store.accessToken, vin: store.vin, phone: store.phone) { [weak self] info in
            guard let self, let info else { return }
            DispatchQueue.main.async {
                self.latestBleKeyInfo = info
                if self.bleStatus != .connected {
                    self.bleStatus = .disconnected
                }
                var dash = self.dashboard
                dash.bleMacText = info["bleMac"] ?? info["macAddress"] ?? dash.bleMacText
                dash.keyIdText = info["keyId"] ?? dash.keyIdText
                dash.keyTypeText = info["keyType"] ?? dash.keyTypeText
                dash.masterKeyMaskedText = self.maskHex(info["masterKey"], visiblePrefix: 4, visibleSuffix: 4)
                dash.randomMaskedText = self.maskHex(info["keyMasterRandom"] ?? info["random"], visiblePrefix: 4, visibleSuffix: 4)
                dash.keyExpiryText = info["expiredTime"] ?? info["expireTime"] ?? info["endTime"] ?? dash.keyExpiryText
                self.applyDashboard(dash)
            }
        }
    }

    // MARK: - MQTT

    private func connectMQTT(_ creds: SGMWApiClient.MQTTCredentials) {
        let mqtt = CocoaMQTT(clientID: creds.clientId, host: creds.broker, port: creds.port)
        mqtt.username = creds.username
        mqtt.password = creds.password
        mqtt.keepAlive = 60
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.delegate = self
        self.mqtt = mqtt
        CrashLogger.shared.mark("MQTT", "connecting clientId=\(creds.clientId)")
        if !mqtt.connect() {
            mqttStatus = .error
            CrashLogger.shared.mark("MQTT", "connect initiate failed")
        }
    }

    private func handleVehicleStatus(_ data: Data) {
        let fields = decodeMQTTFields(data)
        guard !fields.isEmpty else { return }

        var changedKeys: [String] = []
        for (k, v) in fields where lastMqttFields[k] != v {
            changedKeys.append("\(k):\(lastMqttFields[k] ?? "?")→\(v)")
        }
        guard !changedKeys.isEmpty else { return }

        lastMqttFields.merge(fields) { _, new in new }
        let newState = mapMQTTToVehicleState(fields)
        let newDashboard = mapMQTTToDashboard(fields)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected
            self.mergeRealtimeState(newState: newState, dashboard: newDashboard)
            let summary = changedKeys.prefix(6).joined(separator: ", ")
            CrashLogger.shared.mark("MQTT", "state changed: \(summary)")
        }
    }

    private func decodeMQTTFields(_ data: Data) -> [String: String] {
        let decoded = ProtobufDecoder.decode(data)
        let nameMap: [Int: String] = [
            1: "collectTime", 2: "acStatus", 3: "doorLockStatus",
            4: "door1LockStatus", 5: "door2LockStatus", 6: "door3LockStatus", 7: "door4LockStatus", 8: "tailDoorLockStatus",
            9: "door1OpenStatus", 10: "door2OpenStatus", 11: "door3OpenStatus", 12: "door4OpenStatus", 13: "tailDoorOpenStatus",
            14: "window1Status", 15: "window2Status", 16: "window3Status", 17: "window4Status",
            18: "window1OpenDegree", 19: "window2OpenDegree", 20: "window3OpenDegree", 21: "window4OpenDegree"
        ]
        var result: [String: String] = [:]
        for field in decoded {
            guard let name = nameMap[field.fieldNumber] else { continue }
            switch field.wireType {
            case .varint:
                if let val = ProtobufDecoder.int64(field) { result[name] = String(val) }
            case .lengthDelimited:
                if let val = ProtobufDecoder.string(field) { result[name] = val }
            }
        }
        return result
    }

    // MARK: - HTTP/MQTT 映射

    private func mapHTTPToVehicleState(_ s: [String: String]) -> VehicleState {
        var next = state
        next.timestamp = parseTimestamp(s["collectTime"]) ?? Date()
        next.online = true

        if let locked = parseLocked(s["doorLockStatus"]) { next.locked = locked }
        if let doorsClosed = parseDoorClosed(s) { next.doorsClosed = doorsClosed }
        if let driverOpen = parseOpen(s["door1OpenStatus"]) { next.driverDoorOpen = driverOpen }
        if let trunkOpen = parseOpen(s["tailDoorOpenStatus"]) { next.trunkOpen = trunkOpen }
        if let windowsClosed = parseWindowsClosed(s) { next.windowsClosed = windowsClosed }

        if let batterySoc = parseDouble(s["batterySoc"]) { next.fuelLevel = batterySoc }
        if let leftMileage = parseDouble(s["leftMileage"]) { next.fuelRange = leftMileage }
        if let leftFuel = parseDouble(s["leftFuel"]) { next.oilRange = parseDouble(s["oilLeftMileage"]) ?? next.oilRange; next.fuelLevel = next.fuelLevel ?? leftFuel }
        if let oilMileage = parseDouble(s["oilLeftMileage"]) { next.oilRange = oilMileage }

        if let ac = parseACStatus(s["acStatus"]) { next.acOn = ac }
        if let temp = parseDouble(s["accCntTemp"] ?? s["interiorTemperature"]) { next.acTemperature = temp }
        if let gear = parseGear(s["autoGearStatus"]) { next.gear = gear }
        if let speed = parseDouble(s["vehSpdAvgDrvn"] ?? s["speed"]) { next.speed = speed }
        if let keyInside = parseKeyInside(s["keyStatus"]) { next.physicalKeyInside = keyInside }
        if let phoneNearby = parsePhoneNearby(s["keyStatus"]) { next.phoneNearby = phoneNearby }
        if let rssi = parseInt(s["bleRssi"]) { next.bleRssi = rssi }
        if let power = parsePowerState(s) { next.power = power }
        return next
    }

    private func mapHTTPToDashboard(_ s: [String: String]) -> VehicleDashboardState {
        var d = dashboard
        d.updatedAt = parseTimestamp(s["collectTime"]) ?? Date()
        d.updatedAtText = formatTime(d.updatedAt)

        let electricRange = parseInt(s["leftMileage"]) ?? d.electricRangeKm
        let fuelRange = parseInt(s["oilLeftMileage"]) ?? d.fuelRangeKm
        d.electricRangeKm = electricRange
        d.fuelRangeKm = fuelRange
        if let batterySoc = parseInt(s["batterySoc"]) { d.electricFullRangeKm = max(electricRange, Int(Double(electricRange) / max(Double(batterySoc), 1) * 100)) }
        if let leftFuel = parseDouble(s["leftFuel"]), leftFuel > 0 {
            d.fuelFullRangeKm = max(fuelRange, Int(Double(fuelRange) / 0.5))
        }

        d.batteryRemainingText = displayBatteryRemaining(s)
        d.batteryHealthPercentText = displayBatteryHealth(s)
        d.batteryVoltageText = displayValue(s["voltage"], suffix: "V")
        d.batteryAuxText = displayValue(s["lowBatVol"], suffix: "V")

        d.cabinTemperatureText = displayValue(s["interiorTemperature"], suffix: "°C")
        d.acTemperatureText = displayACTemperature(s)
        d.batteryTemperatureText = displayValue(s["batAvgTemp"] ?? s["batMinTemp"], suffix: "°C")
        d.motorTemperatureText = displayValue(s["tmActTemp"], suffix: "°C")
        d.inverterTemperatureText = displayValue(s["invActTemp"], suffix: "°C")

        let charging = s["charging"] == "1"
        d.isCharging = charging
        d.chargingStatusText = charging ? "是" : "否"
        d.chargingPowerText = displayValue(s["chargePower"], suffix: " kW")
        d.chargingPowerValueText = displayValue(s["chargePower"], suffix: " kW")
        d.obcCurrentText = displayValue(s["obcOtpCur"], suffix: "A")
        d.obcTemperatureText = displayValue(s["obcTemp"], suffix: "°C")
        d.chargingStateText = displayText(s["rechargeStatus"]) ?? displayText(s["vecChrgingSts"]) ?? "--"

        d.lockStatusText = (parseLocked(s["doorLockStatus"]) == true) ? "已锁车" : ((parseLocked(s["doorLockStatus"]) == false) ? "未锁" : "未知")
        d.doorStatusText = (parseDoorClosed(s) == true) ? "全关" : ((parseDoorClosed(s) == false) ? "未关" : "未知")
        d.windowStatusText = (parseWindowsClosed(s) == true) ? "全关" : ((parseWindowsClosed(s) == false) ? "未关" : "未知")
        d.tailgateStatusText = (parseOpen(s["tailDoorOpenStatus"]) == true) ? "已开" : ((parseOpen(s["tailDoorOpenStatus"]) == false) ? "已锁" : "未知")

        d.speedText = displayValue(s["vehSpdAvgDrvn"] ?? s["speed"], suffix: "km/h")
        d.steeringAngleText = displayValue(s["strWhAng"], suffix: "°")
        d.throttlePercentText = displayValue(s["accActPos"], suffix: "%")
        d.brakePercentText = displayValue(s["brakPedalPos"], suffix: "%")

        d.lowBeamText = boolText(s["dipHeadLight"])
        d.highBeamText = boolText(s["lowBeamLight"])
        d.leftTurnText = boolText(s["leftTurnLight"])
        d.rightTurnText = boolText(s["rightTurnLight"])
        d.positionLightText = boolText(s["positionLight"])
        d.frontFogText = boolText(s["frontFogLight"])
        return d
    }

    private func mapMQTTToVehicleState(_ s: [String: String]) -> VehicleState {
        var next = state
        next.timestamp = parseTimestamp(s["collectTime"]) ?? Date()
        next.online = true
        if let locked = parseLocked(s["doorLockStatus"]) { next.locked = locked }
        if let doorsClosed = parseDoorClosed(s) { next.doorsClosed = doorsClosed }
        if let driverOpen = parseOpen(s["door1OpenStatus"]) { next.driverDoorOpen = driverOpen }
        if let trunkOpen = parseOpen(s["tailDoorOpenStatus"]) { next.trunkOpen = trunkOpen }
        if let windowsClosed = parseWindowsClosed(s) { next.windowsClosed = windowsClosed }
        if let ac = parseACStatus(s["acStatus"]) { next.acOn = ac }
        return next
    }

    private func mapMQTTToDashboard(_ s: [String: String]) -> VehicleDashboardState {
        var d = dashboard
        if let locked = parseLocked(s["doorLockStatus"]) { d.lockStatusText = locked ? "已锁车" : "未锁" }
        if let doorsClosed = parseDoorClosed(s) { d.doorStatusText = doorsClosed ? "全关" : "未关" }
        if let windowsClosed = parseWindowsClosed(s) { d.windowStatusText = windowsClosed ? "全关" : "未关" }
        if let tailOpen = parseOpen(s["tailDoorOpenStatus"]) { d.tailgateStatusText = tailOpen ? "已开" : "已锁" }
        if let ac = parseACStatus(s["acStatus"]) { d.acTemperatureText = ac ? "开启" : "关闭" }
        d.updatedAt = parseTimestamp(s["collectTime"]) ?? Date()
        d.updatedAtText = formatTime(d.updatedAt)
        return d
    }

    private func mergeHTTPBaseState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        var merged = state
        merged.timestamp = newState.timestamp
        merged.online = newState.online
        merged.gear = newState.gear
        merged.power = newState.power
        merged.speed = newState.speed
        merged.physicalKeyInside = newState.physicalKeyInside
        merged.phoneNearby = newState.phoneNearby
        merged.fuelLevel = newState.fuelLevel
        merged.fuelRange = newState.fuelRange
        merged.oilRange = newState.oilRange
        if merged.locked == nil { merged.locked = newState.locked }
        if merged.doorsClosed == nil { merged.doorsClosed = newState.doorsClosed }
        if merged.driverDoorOpen == nil { merged.driverDoorOpen = newState.driverDoorOpen }
        if merged.trunkOpen == nil { merged.trunkOpen = newState.trunkOpen }
        if merged.windowsClosed == nil { merged.windowsClosed = newState.windowsClosed }
        if merged.acOn == nil { merged.acOn = newState.acOn }
        if merged.acTemperature == nil { merged.acTemperature = newState.acTemperature }
        apply(merged)
        applyDashboard(newDashboard)
    }

    private func mergeRealtimeState(newState: VehicleState, dashboard newDashboard: VehicleDashboardState) {
        var merged = state
        merged.timestamp = newState.timestamp
        merged.online = newState.online
        if newState.locked != nil { merged.locked = newState.locked }
        if newState.doorsClosed != nil { merged.doorsClosed = newState.doorsClosed }
        if newState.driverDoorOpen != nil { merged.driverDoorOpen = newState.driverDoorOpen }
        if newState.trunkOpen != nil { merged.trunkOpen = newState.trunkOpen }
        if newState.windowsClosed != nil { merged.windowsClosed = newState.windowsClosed }
        if newState.acOn != nil { merged.acOn = newState.acOn }
        apply(merged)

        var dash = dashboard
        dash.lockStatusText = newDashboard.lockStatusText
        dash.doorStatusText = newDashboard.doorStatusText
        dash.windowStatusText = newDashboard.windowStatusText
        dash.tailgateStatusText = newDashboard.tailgateStatusText
        dash.acTemperatureText = newDashboard.acTemperatureText
        dash.updatedAt = newDashboard.updatedAt
        dash.updatedAtText = newDashboard.updatedAtText
        applyDashboard(dash)
    }

    private func applyHTTPMeta(carInfo: [String: String], carStatus: [String: String]) {
        if let lat = parseDouble(carStatus["latitude"]), let lng = parseDouble(carStatus["longitude"]), lat != 0, lng != 0 {
            latestLatitude = lat
            latestLongitude = lng
            let addressHint = carStatus["address"]
            if let addressHint, !addressHint.isEmpty {
                latestAddress = addressHint
                shouldPreferCachedAddress = false
            }
            let addressSettings = AddressServiceSettings()
            let hasAmapKey = !addressSettings.amapWebKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasAmapKey {
                shouldPreferCachedAddress = false
                locationResolver.getAddress(wgs84Lat: lat, wgs84Lng: lng, address: nil, amapWebKey: addressSettings.amapWebKey) { [weak self] resolved in
                    guard let self, let resolved else { return }
                    DispatchQueue.main.async {
                        self.latestAddress = resolved
                    }
                }
            }
        }

        var dash = dashboard
        let model = carInfo["carName"]
            ?? carInfo["carModelName"]
            ?? carInfo["carSeriesName"]
            ?? carInfo["carTypeName"]
            ?? ""
        if !model.isEmpty { dash.vehicleName = model }
        dash.vinText = carInfo["vin"] ?? dash.vinText
        dash.userIdText = carInfo["bindCarUserMobile"] ?? carInfo["userId"] ?? dash.userIdText
        if let supportMqtt = carInfo["supportMqtt"], supportMqtt == "1" {
            authStatus = .valid
        }
        if !latestBleKeyInfo.isEmpty, bleStatus == .connecting {
            bleStatus = .disconnected
        }
        applyDashboard(dash)
        applyProfile(VehicleProfile())
    }

    // MARK: - 解析工具

    var mqttClientId: String { credentials?.clientId ?? "" }
    var mqttBrokerDisplayText: String {
        guard let credentials else { return "" }
        return "\(credentials.broker):\(credentials.port)"
    }
    var mqttUsernameMasked: String { maskHex(credentials?.username, visiblePrefix: 4, visibleSuffix: 4) }
    var mqttPasswordMasked: String { maskHex(credentials?.password, visiblePrefix: 4, visibleSuffix: 4) }
    var mqttTopics: [String] { credentials?.topics ?? [] }

    private func parseLocked(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        if raw == "0" { return true }
        if raw == "1" { return false }
        return nil
    }

    private func parseOpen(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        if raw == "0" { return false }
        if raw == "1" { return true }
        return nil
    }

    private func parseDoorClosed(_ s: [String: String]) -> Bool? {
        if let total = parseOpen(s["doorOpenStatus"]) { return !total }
        let values = [s["door1OpenStatus"], s["door2OpenStatus"], s["door3OpenStatus"], s["door4OpenStatus"]]
        let parsed = values.compactMap(parseOpen)
        guard !parsed.isEmpty else { return nil }
        return !parsed.contains(true)
    }

    private func parseWindowsClosed(_ s: [String: String]) -> Bool? {
        if let total = parseOpen(s["windowStatus"]) { return !total }
        let values = [s["window1Status"], s["window2Status"], s["window3Status"], s["window4Status"]]
        let parsed = values.compactMap(parseOpen)
        guard !parsed.isEmpty else { return nil }
        return !parsed.contains(true)
    }

    private func parseACStatus(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw {
        case "0": return false
        case "1", "2": return true
        default: return nil
        }
    }

    private func parseGear(_ raw: String?) -> VehicleGear? {
        guard let raw else { return nil }
        switch raw {
        case "10": return .p
        case "14": return .r
        case "13": return .n
        case "12": return .d
        default: return .unknown
        }
    }

    private func parsePowerState(_ s: [String: String]) -> VehiclePowerState? {
        if let engine = s["engineStatus"] {
            if engine == "1" { return .ready }
            if engine == "0" { return .off }
        }
        return nil
    }

    private func parseKeyInside(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw {
        case "2": return true
        case "0", "1": return false
        default: return nil
        }
    }

    private func parsePhoneNearby(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        return raw != "0"
    }

    private func maskHex(_ raw: String?, visiblePrefix: Int, visibleSuffix: Int) -> String {
        guard let raw, !raw.isEmpty else { return "--" }
        guard raw.count > visiblePrefix + visibleSuffix else { return raw }
        let prefix = raw.prefix(visiblePrefix)
        let suffix = raw.suffix(visibleSuffix)
        return "\(prefix)...\(suffix)"
    }

    private func parseInt(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        return Int(Double(raw) ?? .nan)
    }

    private func parseDouble(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        return Double(raw)
    }

    private func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let ms = Double(raw), ms > 1000000000000 { return Date(timeIntervalSince1970: ms / 1000) }
        if let sec = Double(raw), sec > 1000000000 { return Date(timeIntervalSince1970: sec) }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: raw)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func displayValue(_ raw: String?, suffix: String = "") -> String {
        guard let raw, !raw.isEmpty else { return "--" }
        return raw + suffix
    }

    private func displayText(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private func displayBatteryRemaining(_ s: [String: String]) -> String {
        if let kwh = s["leftBatteryPower"], !kwh.isEmpty { return "\(kwh)kWh" }
        if let soc = s["batterySoc"], !soc.isEmpty { return "\(soc)%" }
        return dashboard.batteryRemainingText
    }

    private func displayBatteryHealth(_ s: [String: String]) -> String {
        if let soh = s["batSOH"] ?? s["batHealth"], !soh.isEmpty { return "\(soh)%" }
        return dashboard.batteryHealthPercentText
    }

    private func boolText(_ raw: String?) -> String {
        guard let raw else { return "--" }
        return raw == "1" ? "开启" : (raw == "0" ? "关闭" : raw)
    }

    private func displayACTemperature(_ s: [String: String]) -> String {
        if let temp = s["interiorTemperature"], !temp.isEmpty { return "\(temp)°C" }
        if let ac = parseACStatus(s["acStatus"]) { return ac ? "开启" : "关闭" }
        return dashboard.acTemperatureText
    }

    // MARK: - 暂保留 mock 控制联动

    override func simulateUnlock() {
        var next = state
        next.locked = false
        apply(next)
        var dash = dashboard
        dash.lockStatusText = "未锁"
        applyDashboard(dash)
    }

    override func simulateLock() {
        var next = state
        next.locked = true
        apply(next)
        var dash = dashboard
        dash.lockStatusText = "已锁车"
        applyDashboard(dash)
    }

    override func simulateToggleAC() {
        var next = state
        next.acOn = !(state.acOn ?? false)
        apply(next)
        var dash = dashboard
        dash.acTemperatureText = next.acOn == true ? "开启" : "关闭"
        applyDashboard(dash)
    }

    override func simulateSetACTemperature(_ temperature: Double) {
        var next = state
        next.acTemperature = temperature
        apply(next)
    }

    override func simulateRemoteStart() {
        var next = state
        next.power = next.power == .off ? .ready : .off
        apply(next)
    }

    override func simulateToggleWindows() {
        var next = state
        next.windowsClosed = !(state.windowsClosed ?? false)
        apply(next)
        var dash = dashboard
        dash.windowStatusText = next.windowsClosed == true ? "全关" : "未关"
        applyDashboard(dash)
    }
}

// MARK: - CocoaMQTTDelegate

extension MQTTVehicleStateStore: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            mqttStatus = .connected
            CrashLogger.shared.mark("MQTT", "connected (ack=\(ack.rawValue))")
            guard let creds = credentials else { return }
            for topic in creds.topics {
                mqtt.subscribe(topic, qos: .qos1)
            }
        } else {
            mqttStatus = .error
            CrashLogger.shared.mark("MQTT", "connect rejected: \(ack.rawValue)")
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let payload = Data(message.payload)
        if message.topic.hasSuffix("/vehicle/app/status") {
            handleVehicleStatus(payload)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        CrashLogger.shared.mark("MQTT", "subscribed \(success.count) topics, failed \(failed.count)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        mqttStatus = .error
        CrashLogger.shared.mark("MQTT", "disconnected: \(err?.localizedDescription ?? "no error")")
    }
}
