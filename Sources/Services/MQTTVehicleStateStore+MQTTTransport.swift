import Foundation
import CocoaMQTT

extension MQTTVehicleStateStore {
    func connectMQTT(_ creds: SGMWApiClient.MQTTCredentials) {
        let mqtt = CocoaMQTT(clientID: creds.clientId, host: creds.broker, port: creds.port)
        mqtt.username = creds.username
        mqtt.password = creds.password
        mqtt.keepAlive = 60
        mqtt.cleanSession = true
        mqtt.autoReconnect = true
        mqtt.delegate = self
        self.mqtt = mqtt
        // connecting 例行不写错误日志；失败才记
        if !mqtt.connect() {
            mqttStatus = .error
            CrashLogger.shared.mark("MQTT", "connect initiate failed")
        }
    }

    func handleVehicleStatus(_ data: Data) {
        let fields = decodeMQTTFields(data)
        guard !fields.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // 官方车端半包有时在锁变化时夹带假门窗翻转；先净化再比较变化
            let sanitizedFields = self.sanitizeMQTTBodyFields(fields)
            var changedKeyNames = Set<String>()
            var changedKeys: [String] = []
            for (k, v) in sanitizedFields where self.lastMqttFields[k] != v {
                changedKeyNames.insert(k)
                changedKeys.append("\(k):\(self.lastMqttFields[k] ?? "?")→\(v)")
            }
            let bodyKeys = [
                "doorLockStatus", "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus",
                "tailDoorOpenStatus", "window1Status", "window2Status", "window3Status", "window4Status",
                "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
                "doorOpenStatus", "windowStatus", "acStatus",
                "engineStatus", "powerStatus", "keyStatus", "batterySoc", "charging", "autoGearStatus"
            ]
            // 没有任何值变化时，不再 force 合并半包（防止旧门窗被反复重写）
            guard !changedKeyNames.isEmpty else { return }

            // 主线程合并，避免 background 读到旧 dashboard 导致门窗回退
            self.lastMqttFields.merge(sanitizedFields) { _, new in new }
            if let collect = parseTimestamp(sanitizedFields["collectTime"]) {
                self.lastMQTTBodyCollectAt = collect
            } else {
                self.lastMQTTBodyCollectAt = Date()
            }
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected
            // MQTT 恢复新鲜后，HTTP 自动降频（下次 timer 重建）
            if let timer = self.httpTimer, abs(timer.timeInterval - Self.httpPollIntervalMQTTFresh) > 0.5 {
                self.startHTTPPolling(immediate: false)
            }

            // 只把“值变化”的字段映射进状态；半包里重复的旧值不再二次写入
            var liveFields: [String: String] = [:]
            if let ct = sanitizedFields["collectTime"] { liveFields["collectTime"] = ct }
            for k in changedKeyNames {
                if let v = sanitizedFields[k] { liveFields[k] = v }
            }
            if liveFields.isEmpty { liveFields = sanitizedFields }

            let newState = self.mapMQTTToVehicleState(liveFields)
            let newDashboard = self.mapMQTTToDashboard(liveFields)
            let collectAt = parseTimestamp(sanitizedFields["collectTime"]) ?? Date()
            self.mergeRealtimeState(
                newState: newState,
                dashboard: newDashboard,
                sourceFields: liveFields,
                collectAt: collectAt,
                changedKeys: changedKeyNames
            )

            let packetKeys = Array(sanitizedFields.keys.sorted()).prefix(10).joined(separator: ",")
            let summary = Array(changedKeys.prefix(8)).joined(separator: ", ")
            // 车身变化只写控制台事件日志，不进错误日志
            let bodyChanged = changedKeyNames.contains { bodyKeys.contains($0) || $0.hasPrefix("door") || $0.hasPrefix("window") || $0.hasPrefix("tailDoor") || $0 == "acStatus" }
            if bodyChanged {
                let detailParts = [
                    "半包=\(packetKeys)",
                    summary,
                    "锁=\(self.dashboard.lockStatusText)",
                    "门=\(self.dashboard.doorStatusText)",
                    "窗=\(self.dashboard.windowStatusText)",
                    "尾=\(self.dashboard.tailgateStatusText)",
                    "主驾=\(self.dashboard.driverDoorStatusText)/副驾=\(self.dashboard.passengerDoorStatusText)/左后=\(self.dashboard.leftRearDoorStatusText)/右后=\(self.dashboard.rightRearDoorStatusText)",
                    "空调=\(self.dashboard.acTemperatureText)",
                    "电=\(self.dashboard.batteryPercentValue.map(String.init) ?? "--")%",
                    "更新=\(self.dashboard.updatedAtText)"
                ]
                let changeIdentity = summary.isEmpty ? packetKeys : summary
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT车身更新",
                    detail: detailParts.joined(separator: " · "),
                    identity: "mqtt-body|\(changeIdentity)",
                    mergeWindow: 90
                )
            }
        }
    }

    /// 过滤车端半包常见噪声：
    /// 1) 锁变化时夹带多门/窗/尾门一起翻开
    /// 2) 单包同时多个门窗“变开”
    /// 3) 与 HTTP 权威全关快照冲突的假开门
    private func sanitizeMQTTBodyFields(_ fields: [String: String]) -> [String: String] {
        var out = fields
        let openKeys = [
            "doorOpenStatus",
            "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus",
            "tailDoorOpenStatus",
            "windowStatus",
            "window1Status", "window2Status", "window3Status", "window4Status"
        ]
        let degreeKeys = [
            "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree"
        ]

        // 与 HTTP 权威快照冲突时，不采纳“突然开”
        if let http = lastHTTPDoorWindowAuthority, Date().timeIntervalSince(http.at) <= 90 {
            for key in openKeys {
                guard let next = parseOpen(out[key]), next == true else { continue }
                if let trusted = parseOpen(http.fields[key]), trusted == false {
                    out.removeValue(forKey: key)
                }
            }
            for key in degreeKeys {
                guard let deg = parseDouble(out[key]), deg > 0 else { continue }
                if let trusted = parseDouble(http.fields[key]), trusted <= 0 {
                    out.removeValue(forKey: key)
                }
            }
        }

        // 本包相对 lastMqttFields 的变化
        var openTrueChanges = 0
        var openFalseChanges = 0
        for key in openKeys {
            guard let next = parseOpen(out[key]) else { continue }
            let prev = parseOpen(lastMqttFields[key])
            if prev != next {
                if next { openTrueChanges += 1 } else { openFalseChanges += 1 }
            }
        }
        for key in degreeKeys {
            let next = parseDouble(out[key]) ?? 0
            let prev = parseDouble(lastMqttFields[key]) ?? 0
            if next > 0 && prev <= 0 { openTrueChanges += 1 }
            if next <= 0 && prev > 0 { openFalseChanges += 1 }
        }

        let lockNext = parseLocked(out["doorLockStatus"])
        let lockPrev = parseLocked(lastMqttFields["doorLockStatus"])
        let lockChanged = (lockNext != nil && lockNext != lockPrev)

        // 锁变化瞬间夹带 ≥2 个“变开”：典型假半包，只保留锁/空调/电源等
        if lockChanged && openTrueChanges >= 2 {
            for key in openKeys + degreeKeys { out.removeValue(forKey: key) }
            return out
        }

        // 没有锁变化时，单包同时 ≥3 个门窗“变开”也极不真实
        if !lockChanged && openTrueChanges >= 3 && openFalseChanges == 0 {
            for key in openKeys + degreeKeys { out.removeValue(forKey: key) }
            return out
        }

        return out
    }

    func handleVehicleControlResult(_ data: Data) {
        guard let result = decodeControlResult(data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mqttStatus = .connected
            self.latestControlResult = result
            // 控制回执走业务层/事件日志，不进错误日志
        }
    }

    private func decodeControlResult(_ data: Data) -> VehicleControlMQTTResult? {
        let decoded = ProtobufDecoder.decode(data)
        guard !decoded.isEmpty else { return decodeJSONControlResult(data) }
        var resultCode = ""
        var message = ""
        var serviceCode = ""
        var timestampMillis: Int64?

        for field in decoded {
            switch field.fieldNumber {
            case 1:
                resultCode = ProtobufDecoder.string(field) ?? ProtobufDecoder.int64(field).map { String($0) } ?? resultCode
            case 2:
                message = ProtobufDecoder.string(field) ?? message
            case 3:
                serviceCode = ProtobufDecoder.string(field) ?? serviceCode
            case 4:
                timestampMillis = ProtobufDecoder.int64(field) ?? timestampMillis
            default:
                continue
            }
        }

        guard !resultCode.isEmpty || !message.isEmpty || !serviceCode.isEmpty else { return decodeJSONControlResult(data) }
        return VehicleControlMQTTResult(resultCode: resultCode, message: message, serviceCode: serviceCode, timestampMillis: timestampMillis, receivedAt: Date())
    }

    private func decodeJSONControlResult(_ data: Data) -> VehicleControlMQTTResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let dataObject = json["data"] as? [String: Any]
        let source = dataObject ?? json
        let resultCode = stringValue(source["resultCode"] ?? source["code"] ?? source["result"])
        let message = stringValue(source["message"] ?? source["msg"])
        let serviceCode = stringValue(source["serviceCode"] ?? source["service"] ?? source["field"])
        let timestampMillis = int64Value(source["timestamp"] ?? source["time"] ?? source["ts"])
        guard !resultCode.isEmpty || !message.isEmpty || !serviceCode.isEmpty else { return nil }
        return VehicleControlMQTTResult(resultCode: resultCode, message: message, serviceCode: serviceCode, timestampMillis: timestampMillis, receivedAt: Date())
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return ""
        }
    }

    private func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        default:
            return nil
        }
    }

    private func decodeMQTTFields(_ data: Data) -> [String: String] {
        // 1) Protobuf（官方主格式）
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
        if !result.isEmpty { return result }

        // 2) JSON 兜底（部分网关/日志链路会推 JSON）
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] {
                let source = (dict["data"] as? [String: Any]) ?? (dict["carStatus"] as? [String: Any]) ?? dict
                for (k, v) in source {
                    switch v {
                    case let s as String:
                        if !s.isEmpty { result[k] = s }
                    case let n as NSNumber:
                        result[k] = n.stringValue
                    case let b as Bool:
                        result[k] = b ? "1" : "0"
                    default:
                        continue
                    }
                }
            }
        }
        return result
    }

    private func mapMQTTToVehicleState(_ s: [String: String]) -> VehicleState {
        VehicleStatusMapper.mqttState(from: s, base: state)
    }

    private func mapMQTTToDashboard(_ s: [String: String]) -> VehicleDashboardState {
        VehicleStatusMapper.mqttDashboard(from: s, base: dashboard)
    }

    func handleMQTTConnectAck(_ mqtt: CocoaMQTT, ack: CocoaMQTTConnAck) {
        if ack == .accept {
            mqttStatus = .connected
            // 连接成功不写错误日志
            guard let creds = credentials else { return }
            for topic in creds.topics {
                mqtt.subscribe(topic, qos: .qos1)
            }
        } else {
            mqttStatus = .error
            CrashLogger.shared.mark("MQTT", "connect rejected: \(ack.rawValue)")
        }
    }

    func handleMQTTReceivedMessage(_ message: CocoaMQTTMessage) {
        let payload = Data(message.payload)
        if message.topic.hasSuffix("/vehicle/app/status") {
            handleVehicleStatus(payload)
        } else if message.topic.hasSuffix("/vehicle/control") {
            handleVehicleControlResult(payload)
        }
    }

    func handleMQTTSubscribedTopics(success: NSDictionary, failed: [String]) {
        // 仅订阅失败进错误日志
        if !failed.isEmpty {
            CrashLogger.shared.mark("MQTT", "subscribe failed topics=\(failed.count)")
        }
    }

    func handleMQTTDisconnect(error: Error?) {
        mqttStatus = .error
        // 有明确错误才写；正常重连断开不刷错误栏
        if let error {
            CrashLogger.shared.mark("MQTT", "disconnected: \(error.localizedDescription)")
        }
    }
}
