import Foundation
import CocoaMQTT

// MARK: - MQTT 车辆状态 Store
// 接入真实 MQTT 数据源，解析 Protobuf VehicleStatus
// 控制类操作仍走 mock（simulate 方法保持基类空实现）

final class MQTTVehicleStateStore: VehicleStateStore {

    // MQTT 连接
    private var mqtt: CocoaMQTT?
    private var credentials: SGMWApiClient.MQTTCredentials?
    private var isConnected = false

    // 上次 MQTT 推送的原始字段（用于去重）
    private var lastMqttFields: [Int: String] = [:]

    // 最新经纬度（供 RadarCardView 使用）
    @Published private(set) var latestLatitude: Double = 0
    @Published private(set) var latestLongitude: Double = 0

    // 定时器：token 过期自动刷新
    private var tokenRefreshTimer: Timer?

    // 地址解析
    private let locationResolver = LocationResolver.shared

    init() {
        super.init(state: .placeholder, dashboard: VehicleDashboardState())
        startAuth()
    }

    // MARK: - 认证流程

    private func startAuth() {
        guard let token = SGMWApiClient.shared.readLocalToken() else {
            CrashLogger.shared.mark("MQTT", "no local token found")
            return
        }

        CrashLogger.shared.mark("MQTT", "token found, querying vehicle info")

        SGMWApiClient.shared.queryDefaultCar(accessToken: token) { [weak self] result in
            guard let self, let result else {
                CrashLogger.shared.mark("MQTT", "failed to query vehicle info")
                return
            }

            CrashLogger.shared.mark("MQTT", "vehicle: \(result.vin)")

            SGMWApiClient.shared.fetchMqttToken(
                accessToken: token,
                vin: result.vin,
                phone: result.phone
            ) { [weak self] mqttToken in
                guard let self, let mqttToken else {
                    CrashLogger.shared.mark("MQTT", "failed to get mqttToken")
                    return
                }

                let creds = SGMWApiClient.shared.generateMQTTCredentials(
                    vin: result.vin,
                    phone: result.phone,
                    mqttToken: mqttToken
                )

                DispatchQueue.main.async {
                    self.credentials = creds
                    self.connect()
                }
            }
        }
    }

    // MARK: - MQTT 连接

    private func connect() {
        guard let creds = credentials else { return }

        let mqtt = CocoaMQTT(clientID: creds.clientId, host: creds.broker, port: creds.port)
        mqtt.username = creds.username
        mqtt.password = creds.password
        mqtt.keepAlive = 60
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.delegate = self

        self.mqtt = mqtt

        CrashLogger.shared.mark("MQTT", "connecting to \(creds.broker):\(creds.port)")

        if mqtt.connect() {
            CrashLogger.shared.mark("MQTT", "connect initiated")
        } else {
            CrashLogger.shared.mark("MQTT", "connect failed to initiate")
        }
    }

    // MARK: - Protobuf 解析

    private func handleVehicleStatus(_ data: Data) {
        let fields = ProtobufDecoder.decode(data)

        // 建立 fieldNumber → value 的字典
        var fieldMap: [Int: String] = [:]
        for field in fields {
            switch field.wireType {
            case .varint:
                if let val = ProtobufDecoder.int64(field) {
                    fieldMap[field.fieldNumber] = String(val)
                }
            case .lengthDelimited:
                if let val = ProtobufDecoder.string(field) {
                    fieldMap[field.fieldNumber] = val
                }
            }
        }

        // 只有字段值变化时才更新
        var changed = false
        for (num, val) in fieldMap {
            if lastMqttFields[num] != val {
                changed = true
                break
            }
        }

        guard changed else { return }

        // 记录变化
        let changedKeys = fieldMap.compactMap { num, val -> String? in
            guard lastMqttFields[num] != val else { return nil }
            return "f\(num):\(lastMqttFields[num] ?? "?")→\(val)"
        }
        lastMqttFields = fieldMap

        // 映射到 VehicleState
        let newState = mapToVehicleState(fieldMap)

        // 映射到 VehicleDashboardState
        let newDashboard = mapToDashboard(fieldMap)

        // 主线程更新
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.apply(newState)
            self.applyDashboard(newDashboard)

            // 更新地址（经纬度变化时）
            if let lat = Double(fieldMap[27] ?? ""), let lng = Double(fieldMap[28] ?? ""), lat != 0, lng != 0 {
                self.latestLatitude = lat
                self.latestLongitude = lng
                let addressSettings = AddressServiceSettings()
                self.locationResolver.getAddress(
                    wgs84Lat: lat,
                    wgs84Lng: lng,
                    amapWebKey: addressSettings.amapWebKey
                ) { _ in }
            }

            // 日志只写关键变化
            if !changedKeys.isEmpty {
                let summary = changedKeys.prefix(5).joined(separator: ", ")
                CrashLogger.shared.mark("MQTT", "state changed: \(summary)")
            }
        }
    }

    // MARK: - 字段映射

    private func mapToVehicleState(_ f: [Int: String]) -> VehicleState {
        var s = state
        s.timestamp = Date()
        s.online = true

        // 门锁 (field 3: doorLockStatus "0"=锁 "1"=解锁)
        s.locked = f[3] == "0"

        // 门开闭 (field 9-12: door1-4OpenStatus, 13: tailDoorOpenStatus)
        let door1Open = f[9] == "1"
        let door2Open = f[10] == "1"
        let door3Open = f[11] == "1"
        let door4Open = f[12] == "1"
        let tailOpen = f[13] == "1"
        s.doorsClosed = !(door1Open || door2Open || door3Open || door4Open)
        s.driverDoorOpen = door1Open
        s.trunkOpen = tailOpen

        // 车窗 (field 14-17: window1-4Status "0"=关 "1"=开)
        let w1 = f[14] == "1"
        let w2 = f[15] == "1"
        let w3 = f[16] == "1"
        let w4 = f[17] == "1"
        s.windowsClosed = !(w1 || w2 || w3 || w4)

        // 空调 (field 2: acStatus "0"=关 "1"=开)
        s.acOn = f[2] == "1"

        // 档位 (field 23: autoGearStatus 10=P 12=D 13=N 14=R)
        s.gear = parseGear(f[23])

        // 钥匙 (field 22: keyStatus 0=远离 1=车外 2=车内)
        s.physicalKeyInside = f[22] == "2"
        s.phoneNearby = f[22] != "0"

        // 电量 (field 24: batterySoc)
        // 里程 (field 25: leftMileage, 26: mileage)
        // 这些用于 dashboard，不直接放 state

        // 车速 (field 未确认)
        // s.speed = ...

        return s
    }

    private func mapToDashboard(_ f: [Int: String]) -> VehicleDashboardState {
        var d = dashboard

        // 电量/续航
        if let socStr = f[24], let soc = Int(socStr) {
            d.electricRangeKm = Int(f[25] ?? "0") ?? 0
        }

        // 门锁状态文字
        d.lockStatusText = f[3] == "0" ? "已锁车" : "未锁"

        // 门开闭
        let doors = [f[9], f[10], f[11], f[12]]
        d.doorStatusText = doors.contains("1") ? "未关" : "全关"

        // 车窗
        let windows = [f[14], f[15], f[16], f[17]]
        d.windowStatusText = windows.contains("1") ? "未关" : "全关"

        // 尾门
        d.tailgateStatusText = f[13] == "1" ? "已开" : "已锁"

        // 空调
        d.acTemperatureText = f[2] == "1" ? "开启" : "关闭"

        // 档位
        let gear = parseGear(f[23])
        // 不直接改 dashboard 的 gear 字段（如果有的话）

        // 更新时间
        d.updatedAt = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        d.updatedAtText = formatter.string(from: Date())

        return d
    }

    private func parseGear(_ value: String?) -> VehicleGear {
        switch value {
        case "10": return .p
        case "14": return .r
        case "13": return .n
        case "12": return .d
        default:   return .unknown
        }
    }

    // MARK: - 控制类（保持 mock 空实现，不覆盖基类）

    // MARK: - 临时 Mock 控制（真实车控接入前，保持 UI 联动）

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
            isConnected = true
            CrashLogger.shared.mark("MQTT", "connected (ack=\(ack.rawValue))")

            // 订阅所有 topic
            guard let creds = credentials else { return }
            for topic in creds.topics {
                mqtt.subscribe(topic, qos: .qos1)
                CrashLogger.shared.mark("MQTT", "subscribed: \(topic)")
            }
        } else {
            CrashLogger.shared.mark("MQTT", "connect rejected: \(ack.rawValue)")
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let payload = Data(message.payload)

        let topic = message.topic
        if topic.hasSuffix("/vehicle/app/status") {
            handleVehicleStatus(payload)
        } else if topic.hasSuffix("/vehicle/control") {
            // ControlResult — 暂不处理
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        CrashLogger.shared.mark("MQTT", "subscribed \(success.count) topics, failed \(failed.count)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {}

    func mqttDidPing(_ mqtt: CocoaMQTT) {}

    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        isConnected = false
        CrashLogger.shared.mark("MQTT", "disconnected: \(err?.localizedDescription ?? "no error")")
        // CocoaMQTT autoReconnect 会自动重连
    }
}
