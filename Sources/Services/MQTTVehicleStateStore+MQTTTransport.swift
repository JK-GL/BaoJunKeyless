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
        CrashLogger.shared.mark("MQTT", "connecting clientId=\(creds.clientId)")
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

            var changedKeyNames = Set<String>()
            var changedKeys: [String] = []
            for (k, v) in fields where self.lastMqttFields[k] != v {
                changedKeyNames.insert(k)
                changedKeys.append("\(k):\(self.lastMqttFields[k] ?? "?")→\(v)")
            }
            // 即使 collectTime 等杂项无变化，门窗字段只要有值也强制合并一次（防丢包后不刷新）
            let bodyKeys = [
                "doorLockStatus", "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus",
                "tailDoorOpenStatus", "window1Status", "window2Status", "window3Status", "window4Status",
                "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
                "doorOpenStatus", "windowStatus", "acStatus"
            ]
            let hasBody = bodyKeys.contains { fields[$0] != nil }
            // 没有任何值变化时，不再 force 合并半包（防止旧门窗被反复重写）
            guard !changedKeyNames.isEmpty else { return }
            _ = hasBody

            // 主线程合并，避免 background 读到旧 dashboard 导致门窗回退
            self.lastMqttFields.merge(fields) { _, new in new }
            if let collect = parseTimestamp(fields["collectTime"]) {
                self.lastMQTTBodyCollectAt = collect
            } else {
                self.lastMQTTBodyCollectAt = Date()
            }
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected

            // 只把“值变化”的字段映射进状态；半包里重复的旧值不再二次写入
            // 这样 HTTP 纠正后，不会被下一包相同旧门字段重新钉死
            var liveFields = fields
            if !changedKeyNames.isEmpty {
                // 保留 collectTime + 变化字段
                var filtered: [String: String] = [:]
                if let ct = fields["collectTime"] { filtered["collectTime"] = ct }
                for k in changedKeyNames {
                    if let v = fields[k] { filtered[k] = v }
                }
                // 若只有 collectTime 变化，仍允许空车身（后面 hasBody 可能为 true 但无变化）
                liveFields = filtered.isEmpty ? fields : filtered
            }

            let newState = self.mapMQTTToVehicleState(liveFields)
            let newDashboard = self.mapMQTTToDashboard(liveFields)
            let collectAt = parseTimestamp(fields["collectTime"]) ?? Date()
            self.mergeRealtimeState(
                newState: newState,
                dashboard: newDashboard,
                sourceFields: liveFields,
                collectAt: collectAt,
                changedKeys: changedKeyNames
            )

            let packetKeys = Array(fields.keys.sorted()).prefix(10).joined(separator: ",")
            let summary = (changedKeys.isEmpty ? Array(fields.keys.prefix(8)).map { "\($0)=force" } : Array(changedKeys.prefix(8))).joined(separator: ", ")
            CrashLogger.shared.mark("MQTT", "state changed: \(summary)")
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
                // 有字段变化才记；相同变化短时间合并 ×N，避免刷屏
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

    func handleVehicleControlResult(_ data: Data) {
        guard let result = decodeControlResult(data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mqttStatus = .connected
            self.latestControlResult = result
            CrashLogger.shared.mark("MQTT", "control result: \(result.displayDetail)")
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

    func handleMQTTReceivedMessage(_ message: CocoaMQTTMessage) {
        let payload = Data(message.payload)
        if message.topic.hasSuffix("/vehicle/app/status") {
            handleVehicleStatus(payload)
        } else if message.topic.hasSuffix("/vehicle/control") {
            handleVehicleControlResult(payload)
        }
    }

    func handleMQTTSubscribedTopics(success: NSDictionary, failed: [String]) {
        CrashLogger.shared.mark("MQTT", "subscribed \(success.count) topics, failed \(failed.count)")
    }

    func handleMQTTDisconnect(error: Error?) {
        mqttStatus = .error
        CrashLogger.shared.mark("MQTT", "disconnected: \(error?.localizedDescription ?? "no error")")
    }
}
