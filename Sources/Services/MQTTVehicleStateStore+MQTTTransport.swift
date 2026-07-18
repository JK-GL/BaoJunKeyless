import Foundation
import CocoaMQTT

extension MQTTVehicleStateStore {
    func connectMQTT(_ creds: SGMWApiClient.MQTTCredentials) {
        guard keylessSettingsStore.settings.mqttEnabled else {
            mqttStatus = .disconnected
            return
        }
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
        guard keylessSettingsStore.settings.mqttEnabled else { return }
        let rawFields = decodeMQTTFields(data)
        guard !rawFields.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.keylessSettingsStore.settings.mqttEnabled else { return }

            // 对齐官方 receiveMQTTCarStatus：先滤噪声半包，再即时更新 UI。
            // 官方日志：车况通知 →「更新所有状态」；HTTP 轮询只作补齐/收敛。
            let fields = self.sanitizeMQTTBodyFields(rawFields)
            guard !fields.isEmpty else { return }

            var changes: [String] = []
            var changedKeys = Set<String>()
            for (key, value) in fields where key != "collectTime" && self.lastMqttFields[key] != value {
                changes.append("\(key):\(self.lastMqttFields[key] ?? "?")→\(value)")
                changedKeys.insert(key)
            }
            // 无变化的心跳包：只刷新在线时间，不刷 UI / 不打 HTTP
            let collectAt = parseTimestamp(fields["collectTime"]) ?? Date()
            self.lastMqttFields.merge(fields) { _, new in new }
            self.lastMQTTBodyCollectAt = collectAt
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected
            guard !changes.isEmpty else { return }

            // 1) 电源：明确字段即时写（本车型 engineStatus 常空，有则用）
            if fields["engineStatus"] != nil
                || fields["powerStatus"] != nil
                || fields["vehPowerMode"] != nil
                || fields["vehiclePowerStatus"] != nil
                || fields["sysPowerMode"] != nil
                || fields["ignitionStatus"] != nil,
               let power = parsePowerState(fields) {
                self.ingestExplicitPowerLocal(power, source: "MQTT电源字段")
            }

            // 2) 空调：即时
            let climateAc = parseACStatus(fields["acStatus"])
            let climateTemp = parseDouble(fields["accCntTemp"])
            var climateChanged = false
            if climateAc != nil || climateTemp != nil {
                climateChanged = self.applyAuthoritativeClimateState(
                    acOn: climateAc,
                    temperature: climateTemp,
                    source: "MQTT空调推送",
                    observedAt: collectAt,
                    scheduleHTTPConfirm: false
                )
            }

            // 3) 门锁/门/窗/尾门/灯光等车身：官方同路径即时写 UI
            //    本机 BLE/HTTP 锁保护窗外：MQTT 锁变化也即时（旁观不加 15s hold）
            let bodyKeys: Set<String> = [
                "doorLockStatus",
                "doorOpenStatus", "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus",
                "door1LockStatus", "door2LockStatus", "door3LockStatus", "door4LockStatus",
                "tailDoorOpenStatus", "tailDoorLockStatus",
                "windowStatus", "window1Status", "window2Status", "window3Status", "window4Status",
                "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
                "window1HalfOpenStatus", "window2HalfOpenStatus", "window3HalfOpenStatus", "window4HalfOpenStatus",
                "windowHalfOpenStatus",
                "keyStatus", "autoGearStatus",
                "lowBeamLight", "dipHeadLight", "leftTurnLight", "rightTurnLight", "positionLight", "frontFogLight",
                "batterySoc", "leftMileage", "oilLeftMileage", "mileage",
                "charging", "chargePower", "vecChrgingSts", "vecChrgStsIndOn", "wireConnect",
                "leftFuel", "voltage", "lowBatVol", "batAvgTemp", "tmActTemp", "invActTemp",
                "interiorTemperature", "accCntTemp"
            ]
            let bodyChanged = !changedKeys.isDisjoint(with: bodyKeys)
            if bodyChanged {
                // 门锁：若本包带明确 doorLockStatus，走旁观即时写（不挡后续网络）
                if let locked = parseLocked(fields["doorLockStatus"]),
                   changedKeys.contains("doorLockStatus") {
                    let holdActive = self.localDoorLockHoldUntil.map { Date() < $0 } ?? false
                    if !holdActive {
                        self.ingestBLEDoorLockLocal(
                            locked: locked,
                            source: "MQTT门锁推送",
                            suppressOppositeKeyless: false,
                            protectAgainstNetworkOverride: false
                        )
                    }
                }

                let mappedState = self.mapMQTTToVehicleState(fields)
                let mappedDash = self.mapMQTTToDashboard(fields)
                self.mergeRealtimeState(
                    newState: mappedState,
                    dashboard: mappedDash,
                    sourceFields: fields,
                    collectAt: collectAt,
                    changedKeys: changedKeys
                )

                let summary = Array(changes.prefix(8)).joined(separator: ", ")
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 即时更新",
                    detail: "对齐官方更新所有状态 · \(summary)",
                    identity: "mqtt-live|\(summary)",
                    mergeWindow: 8
                )
            } else if climateChanged {
                let summary = Array(changes.prefix(6)).joined(separator: ", ")
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 即时更新",
                    detail: "空调 · \(summary)",
                    identity: "mqtt-climate|\(summary)",
                    mergeWindow: 8
                )
            } else {
                let summary = Array(changes.prefix(6)).joined(separator: ", ")
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 状态提示",
                    detail: summary,
                    identity: "mqtt-hint|\(summary)",
                    mergeWindow: 30
                )
            }

            // 4) 仍触发 HTTP 补齐（电量/位置等）与最终权威收敛；不替代上面的即时 UI
            self.scheduleHTTPRefreshFromRealtime(reason: "mqtt-status")
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
        // 官方 App 日志里 receiveMQTTCarStatus 是完整 JSON（约 80+ 字段）并「更新所有状态」。
        // 线上可能是 Protobuf 或 JSON：两边都解，取字段更全的一份，避免 PB 半图挡住完整 JSON。
        let protobufFields = decodeProtobufMQTTFields(data)
        let jsonFields = decodeJSONMQTTFields(data)
        if jsonFields.count > protobufFields.count { return jsonFields }
        if !protobufFields.isEmpty { return protobufFields }
        return jsonFields
    }

    private func decodeProtobufMQTTFields(_ data: Data) -> [String: String] {
        let decoded = ProtobufDecoder.decode(data)
        // 与历史逆向一致的车身核心字段；其余字段走 JSON 路径或 HTTP 补齐
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
            case .fixed64, .fixed32:
                continue
            }
        }
        return result
    }

    private func decodeJSONMQTTFields(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return result }
        guard let dict = json as? [String: Any] else { return result }
        let source = (dict["data"] as? [String: Any]) ?? (dict["carStatus"] as? [String: Any]) ?? dict
        for (k, v) in source {
            switch v {
            case let s as String:
                // 官方空串表示“本字段无值”，保留空串不利于半包判断；仅非空入库
                if !s.isEmpty { result[k] = s }
            case let n as NSNumber:
                result[k] = n.stringValue
            case let b as Bool:
                result[k] = b ? "1" : "0"
            default:
                continue
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
        guard self.mqtt === mqtt else { return }
        guard keylessSettingsStore.settings.mqttEnabled else {
            mqtt.autoReconnect = false
            mqtt.disconnect()
            mqttStatus = .disconnected
            return
        }
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

    func handleMQTTReceivedMessage(_ sourceClient: CocoaMQTT, message: CocoaMQTTMessage) {
        guard mqtt === sourceClient, keylessSettingsStore.settings.mqttEnabled else { return }
        let payload = Data(message.payload)
        if message.topic.hasSuffix("/vehicle/app/status") {
            // 水管2：MQTT 状态进水（语义同 handleVehicleStatus）
            ingestMQTTStatusPayload(payload)
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

    func handleMQTTDisconnect(_ disconnectedClient: CocoaMQTT, error: Error?) {
        // 手动重连时旧 client 的断开回调不能把新连接状态改成 error。
        guard mqtt === disconnectedClient else { return }
        guard keylessSettingsStore.settings.mqttEnabled else {
            mqttStatus = .disconnected
            return
        }
        mqttStatus = .error
        // 有明确错误才写；正常重连断开不刷错误栏
        if let error {
            CrashLogger.shared.mark("MQTT", "disconnected: \(error.localizedDescription)")
        }
    }
}
