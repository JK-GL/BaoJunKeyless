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
        let fields = decodeMQTTFields(data)
        guard !fields.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.keylessSettingsStore.settings.mqttEnabled else { return }

            // 合并 lastMqtt 之前先判定：干净门锁变化 / 门窗脏半包（须用合并前基线）
            let lockInstant = self.evaluateMQTTDoorLockInstant(fields)

            var changes: [String] = []
            for (key, value) in fields where key != "collectTime" && self.lastMqttFields[key] != value {
                changes.append("\(key):\(self.lastMqttFields[key] ?? "?")→\(value)")
            }
            self.lastMqttFields.merge(fields) { _, new in new }
            self.lastMQTTBodyCollectAt = parseTimestamp(fields["collectTime"]) ?? Date()
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected

            // 唯一允许 MQTT 直接更新的车辆状态：明确的 engineStatus/电源字段。
            // 它是完整单值而非门窗半包；HTTP 本车型不返回时用于真实区分熄火/上电。
            if fields["engineStatus"] != nil
                || fields["powerStatus"] != nil
                || fields["vehPowerMode"] != nil
                || fields["vehiclePowerStatus"] != nil
                || fields["sysPowerMode"] != nil
                || fields["ignitionStatus"] != nil,
               let power = parsePowerState(fields) {
                self.ingestExplicitPowerLocal(power, source: "MQTT电源字段")
            }

            // 空调开关/设定温度：MQTT 真实字段即时回写。
            // 同值重复推送不会写 UI；仅真实变化才补 HTTP。
            let climateAc = parseACStatus(fields["acStatus"])
            let climateTemp = parseDouble(fields["accCntTemp"])
            let climateObservedAt = parseTimestamp(fields["collectTime"]) ?? Date()
            var climateChanged = false
            if climateAc != nil || climateTemp != nil {
                climateChanged = self.applyAuthoritativeClimateState(
                    acOn: climateAc,
                    temperature: climateTemp,
                    source: "MQTT空调推送",
                    observedAt: climateObservedAt,
                    scheduleHTTPConfirm: true
                )
            }

            // doorLockStatus 变化：立刻写锁（像空调）；门窗永不从 MQTT 半包上屏。
            var lockInstantApplied = false
            if let locked = lockInstant {
                lockInstantApplied = self.applyMQTTDoorLockInstantIfAllowed(locked)
            }

            // 其他 MQTT 半包不直接写车辆状态；只提示变化并唤醒 HTTP 完整快照。
            // 空调/门锁总态已单独处理；门窗等仍只提示 + HTTP 权威补齐。
            let nonClimateChanges = changes.filter {
                !$0.hasPrefix("acStatus:") && !$0.hasPrefix("accCntTemp:")
            }
            guard !nonClimateChanges.isEmpty || lockInstantApplied else { return }
            if !nonClimateChanges.isEmpty {
                let summary = Array(nonClimateChanges.prefix(8)).joined(separator: ", ")
                let lockNote = lockInstantApplied ? " · 门锁已即时更新" : ""
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 状态提示",
                    detail: "检测到增量变化 · \(summary)\(lockNote) · 正在触发 HTTP 确认",
                    identity: "mqtt-hint|\(summary)",
                    mergeWindow: 60
                )
            }
            // 锁变化：立刻 poll 一次（别只靠 0.8s 防抖），再 schedule 补刀；补门窗与权威。
            if lockInstantApplied {
                self.pollHTTPOnce(userInitiated: false, completion: nil)
                self.scheduleHTTPRefreshFromRealtime(reason: "mqtt-door-lock-instant")
            } else if !climateChanged || !nonClimateChanges.isEmpty {
                self.scheduleHTTPRefreshFromRealtime(reason: "mqtt-status")
            }
        }
    }

    /// 合并前判定：本包是否带来可即时上屏的锁态。
    ///
    /// 1) **总锁 `doorLockStatus` 优先且足够**（相对 lastMqtt 有变化）→ 直接用
    /// 2) 仅当本包**没有**总锁字段时，才用分门锁推断（官方上锁常见）
    ///    - 本包至少 2 个分门锁字段，且聚合后全为「已锁」才推断已锁
    ///    - **禁止**用「单个 door4LockStatus」把整车打成已锁（开锁半包会抖）
    ///    - 分锁路径**只用于 →已锁**，不用于 →未锁（开锁必须有总锁 0→1）
    /// 3) 门窗开闭永不在此上屏
    ///
    /// - 返回 `nil`：无可用锁变化
    /// - 返回 Bool：目标锁态（true=已锁）
    private func evaluateMQTTDoorLockInstant(_ fields: [String: String]) -> Bool? {
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
        // 仅车身四门锁参与「整车已锁」推断；尾门锁单独变化不代表整车已锁
        let perDoorLockKeys = [
            "door1LockStatus", "door2LockStatus", "door3LockStatus", "door4LockStatus"
        ]

        var openTrueChanges = 0
        for key in openKeys {
            guard let next = parseOpen(fields[key]) else { continue }
            let prev = parseOpen(lastMqttFields[key])
            if prev != next, next { openTrueChanges += 1 }
        }
        for key in degreeKeys {
            let next = parseDouble(fields[key]) ?? 0
            let prev = parseDouble(lastMqttFields[key]) ?? 0
            if next > 0 && prev <= 0 { openTrueChanges += 1 }
        }
        if openTrueChanges >= 2 {
            vehicleEventLogStore.addCoalesced(
                .action,
                "MQTT 门锁半包注记",
                detail: "锁相关包夹带 \(openTrueChanges) 处门窗变开 · 仅即时写锁、门窗等 HTTP",
                identity: "mqtt-lock-dirty-note",
                mergeWindow: 30
            )
        }

        // 1) 总锁字段：权威即时信号（开锁/关锁都认）
        if fields["doorLockStatus"] != nil, let lockNext = parseLocked(fields["doorLockStatus"]) {
            let lockPrev = parseLocked(lastMqttFields["doorLockStatus"])
            if lockPrev != lockNext {
                return lockNext
            }
            // 总锁在包里且未变：不要再用分锁去改结论（避免 总锁=未锁 时 door4=锁 把 UI 打成已锁）
            return nil
        }

        // 2) 无总锁字段：仅推断「→已锁」（官方上锁）；开锁必须走总锁
        var changedLockedDoors = 0
        var parsedLocked: [Bool] = []
        for key in perDoorLockKeys {
            guard let next = parseLocked(fields[key]) else { continue }
            parsedLocked.append(next)
            let prev = parseLocked(lastMqttFields[key])
            if prev != next, next == true {
                changedLockedDoors += 1
            }
        }
        // 至少 2 扇分门锁在本包变为「锁」，且本包出现的分锁全为已锁
        guard changedLockedDoors >= 2, !parsedLocked.isEmpty, parsedLocked.allSatisfy({ $0 }) else {
            return nil
        }
        if state.locked == true { return nil }

        vehicleEventLogStore.addCoalesced(
            .action,
            "MQTT 分门锁推断",
            detail: "无总锁 · \(changedLockedDoors)扇分锁变锁 → 已锁",
            identity: "mqtt-lock-per-door",
            mergeWindow: 15
        )
        return true
    }

    /// MQTT 旁观写锁：改 UI，**不**开 15s 网络保护（否则解锁后官方再上锁会被 HTTP 卡住）。
    /// 本机 BLE/HTTP 操作的保护窗仍会挡住「反向」MQTT，避免刚本地操作被半包撕掉。
    /// 另：2.5s 内不接受「反向」MQTT 锁（防开锁过程中分锁/总锁半包连闪）。
    @discardableResult
    private func applyMQTTDoorLockInstantIfAllowed(_ locked: Bool) -> Bool {
        if let current = state.locked, current == locked {
            return false
        }
        // 旁观防抖：刚写过反向锁，短时间忽略对面（半包连推）
        if let at = lastMQTTDoorLockInstantAt,
           let prev = lastMQTTDoorLockInstantValue,
           prev != locked,
           Date().timeIntervalSince(at) < 2.5 {
            vehicleEventLogStore.addCoalesced(
                .action,
                "MQTT 门锁跳过即时写",
                detail: "防抖 \(String(format: "%.1f", Date().timeIntervalSince(at)))s 内不反向 · 保持 \(prev ? "已锁" : "未锁")",
                identity: "mqtt-lock-skip-debounce",
                mergeWindow: 5
            )
            return false
        }
        // 仅当「本机操作保护窗」仍在时，拒绝 MQTT 反向；旁观写锁本身不再延长该窗
        if let holdUntil = localDoorLockHoldUntil, Date() < holdUntil,
           let current = state.locked, current != locked {
            let src = fieldSource["doorLockStatus"] ?? "本地"
            // 只有 BLE/HTTP 本机来源才挡；若来源已是 MQTT 则允许覆盖
            if src == "BLE" || src == "HTTP" {
                vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 门锁跳过即时写",
                    detail: "本机锁保护中(\(src)) · 保持 \(current ? "已锁" : "未锁")",
                    identity: "mqtt-lock-skip-hold",
                    mergeWindow: 15
                )
                return false
            }
        }

        // 外部/官方上锁：在写入前识别（observe 要求当前仍为未锁）
        if locked == true {
            observeAuthoritativeLockState(true)
        }

        ingestBLEDoorLockLocal(
            locked: locked,
            source: "MQTT门锁推送",
            suppressOppositeKeyless: false,
            protectAgainstNetworkOverride: false
        )
        lastMQTTDoorLockInstantAt = Date()
        lastMQTTDoorLockInstantValue = locked
        return true
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
        // 1) Protobuf（主格式）
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
            case .fixed64, .fixed32:
                // 当前已验证的车辆状态字段均为 varint 或 string；固定宽度字段仅跳过。
                continue
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
