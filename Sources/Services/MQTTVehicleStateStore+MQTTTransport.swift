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
        let decoded = decodeMQTTPayload(data)
        // 业务只采纳非空字段：PB 稀疏包没带/空串都不覆盖现有好值；0/1 是有效枚举值。
        let fields = decoded.nonEmptyFields
        let logFields = decoded.allFields.isEmpty ? fields : decoded.allFields
        guard !fields.isEmpty || !logFields.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.keylessSettingsStore.settings.mqttEnabled else { return }

            let previousFields = self.lastMqttFields
            let collectAt = parseTimestamp(fields["collectTime"] ?? logFields["collectTime"]) ?? Date()
            var changedKeys: [String] = []
            for (key, value) in fields where key != "collectTime" && previousFields[key] != value {
                changedKeys.append(key)
            }
            let changedSet = Set(changedKeys)

            // 收包时间只反映 MQTT 链路活性；车身字段基线、车身时间和控制确认必须等 merge 接受后再推进。
            self.lastMQTTUpdate = Date()
            self.mqttStatus = .connected

            let mqttState = VehicleStatusMapper.mqttState(from: fields, base: self.state)
            let mqttDashboard = VehicleStatusMapper.mqttDashboard(from: fields, base: self.dashboard)
            let accepted = self.mergeRealtimeState(
                newState: mqttState,
                dashboard: mqttDashboard,
                sourceFields: fields,
                collectAt: collectAt,
                changedKeys: changedSet
            )
            // 旧 collectTime 包不得污染差异基线、确认当前命令或唤醒 HTTP。
            guard accepted else { return }
            self.lastMqttFields.merge(fields) { _, new in new }
            // MQTT app/status 已即时写 UI；同一包若命中本次 HTTP 控制期望态，立刻确认。
            self.confirmPendingControlStateIfMatched(
                fields: fields,
                source: .mqttStatus,
                observedAt: collectAt
            )
            // 无感锁/解：开 MQTT 时 status 命中目标态立刻推成功通知。
            self.confirmPendingKeylessFromMQTTIfMatched(
                fields: fields,
                observedAt: collectAt
            )
            if fields.keys.contains(where: { ["engineStatus", "powerStatus", "vehPowerMode", "vehiclePowerStatus", "sysPowerMode", "ignitionStatus"].contains($0) }),
               let power = parsePowerState(fields), power != .unknown {
                self.lastExplicitPowerStateAt = collectAt
                self.lastExplicitPowerStateSource = "MQTT电源字段"
            }
            if changedSet.contains("acStatus") || changedSet.contains("accCntTemp") {
                self.lastMQTTClimateAt = max(self.lastMQTTClimateAt ?? .distantPast, collectAt)
            }

            if !decoded.unmappedFieldNumbers.isEmpty {
                self.vehicleEventLogStore.add(
                    .warning,
                    "MQTT 未映射字段",
                    detail: self.formatMQTTOfficialStyleLog(
                        allFields: logFields,
                        previous: previousFields,
                        changedKeys: changedSet,
                        format: decoded.format,
                        payloadBytes: data.count,
                        rawJSON: decoded.rawJSONText,
                        rawHex: decoded.rawHex,
                        pbWireDump: decoded.pbWireDump,
                        unmappedFieldNumbers: decoded.unmappedFieldNumbers
                    )
                )
            }

            let shortDetail = self.formatMQTTStatusShortLog(
                fields: fields,
                previous: previousFields,
                changedKeys: changedSet,
                format: decoded.format,
                payloadBytes: data.count,
                unmappedFieldNumbers: decoded.unmappedFieldNumbers
            )
            let keylessCriticalKeys: Set<String> = [
                "doorLockStatus", "door1LockStatus", "door2LockStatus", "door3LockStatus", "door4LockStatus", "tailDoorLockStatus",
                "doorOpenStatus", "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus", "tailDoorOpenStatus",
                "leftSlidingDoorStatus", "rightSlidingDoorStatus", "topWindowStatus",
                "windowStatus", "window1Status", "window2Status", "window3Status", "window4Status",
                "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
                "windowHalfOpenStatus", "window1HalfOpenStatus", "window2HalfOpenStatus", "window3HalfOpenStatus", "window4HalfOpenStatus",
                "acStatus", "accCntTemp", "acWindGear",
                "engineStatus", "powerStatus", "vehPowerMode", "vehiclePowerStatus", "sysPowerMode", "ignitionStatus",
                "autoGearStatus", "manualGearStatus", "keyStatus",
                "charging", "chargePower", "wireConnect", "vecChrgingSts"
            ]
            let hasKeylessCriticalChange = !changedSet.isDisjoint(with: keylessCriticalKeys)
            if changedKeys.isEmpty {
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 车况同步",
                    detail: shortDetail,
                    identity: "mqtt-status-unchanged|\(decoded.format)",
                    mergeWindow: 120
                )
            } else if !hasKeylessCriticalChange {
                let auxiliaryDetail = self.formatMQTTAuxiliaryStatusLog(
                    fields: fields,
                    previous: previousFields,
                    changedKeys: changedSet,
                    format: decoded.format,
                    payloadBytes: data.count
                )
                self.vehicleEventLogStore.addCoalesced(
                    .action,
                    "MQTT 辅助状态更新",
                    detail: auxiliaryDetail,
                    identity: "mqtt-auxiliary|\(decoded.format)|\(changedSet.sorted().joined(separator: ","))",
                    mergeWindow: 60
                )
                // 日志虽然合并，原有“任一 MQTT 变化后 HTTP 补齐”行为必须保留。
                self.scheduleHTTPRefreshFromRealtime(reason: "mqtt-status")
            } else {
                self.vehicleEventLogStore.add(
                    .action,
                    "MQTT 车况同步",
                    detail: shortDetail
                )
                self.scheduleHTTPRefreshFromRealtime(reason: "mqtt-status")
            }
        }
    }

    /// 官方风格完整字段日志（中文注解 + 全键列表 / raw hex / PB 字段号）
    private func formatMQTTOfficialStyleLog(
        allFields: [String: String],
        previous: [String: String],
        changedKeys: Set<String>,
        format: String,
        payloadBytes: Int,
        rawJSON: String?,
        rawHex: String?,
        pbWireDump: String?,
        unmappedFieldNumbers: [Int]
    ) -> String {
        let collect = allFields["collectTime"].flatMap { $0.isEmpty ? nil : $0 } ?? "无"
        let fieldCount = allFields.count
        let nonEmptyCount = allFields.values.filter { !$0.isEmpty }.count

        var parts: [String] = []
        // 对齐官方三行语义 + 诊断元数据
        parts.append("格式=\(format) · payload=\(payloadBytes)B · 字段数=\(fieldCount)（非空\(nonEmptyCount)）")
        if !unmappedFieldNumbers.isEmpty {
            let nums = unmappedFieldNumbers.map(String.init).joined(separator: ",")
            parts.append("未映射PB字段号=[\(nums)]（官方 map 1…82 以外）")
        } else if format.contains("protobuf") {
            parts.append("未映射PB字段号=[]（均在官方 1…82 内）")
        }
        parts.append("车况时间-mqtt：\(collect)")
        if changedKeys.isEmpty {
            parts.append("车况通知：无字段变化（心跳/重复包）")
        } else {
            parts.append("车况通知：有变化 · 对齐官方「更新所有状态」数据源（MQTT已回写UI，HTTP补齐收敛）")
        }

        // 中文关键快照
        parts.append(formatMQTTStatusChinese(fields: allFields, previous: previous, changedKeys: changedKeys))

        // 完整字段表（中文名=值），按键排序，尽量像官方整包可读
        let zhName: [String: String] = [
            "doorLockStatus": "总锁", "door1LockStatus": "主驾锁", "door2LockStatus": "副驾锁",
            "door3LockStatus": "左后锁", "door4LockStatus": "右后锁", "tailDoorLockStatus": "尾门锁",
            "doorOpenStatus": "总门", "door1OpenStatus": "主驾门", "door2OpenStatus": "副驾门",
            "door3OpenStatus": "左后门", "door4OpenStatus": "右后门", "tailDoorOpenStatus": "尾门",
            "leftSlidingDoorStatus": "左滑门", "rightSlidingDoorStatus": "右滑门",
            "windowStatus": "总窗", "window1Status": "主驾窗", "window2Status": "副驾窗",
            "window3Status": "左后窗", "window4Status": "右后窗",
            "window1OpenDegree": "主驾窗开度", "window2OpenDegree": "副驾窗开度",
            "window3OpenDegree": "左后窗开度", "window4OpenDegree": "右后窗开度",
            "window1HalfOpenStatus": "主驾窗半开", "window2HalfOpenStatus": "副驾窗半开",
            "window3HalfOpenStatus": "左后窗半开", "window4HalfOpenStatus": "右后窗半开",
            "windowHalfOpenStatus": "半开总", "topWindowStatus": "天窗",
            "acStatus": "空调", "accCntTemp": "设定温度", "acTemperatureGear": "空调温度档",
            "acWindGear": "空调风量档", "interiorTemperature": "车内温度",
            "engineStatus": "发动机", "keyStatus": "钥匙", "autoGearStatus": "自动档",
            "manualGearStatus": "手动档", "batterySoc": "电量%", "batSoh": "电池SOH",
            "leftBatteryPower": "剩余电量kWh", "leftMileage": "电续航", "oilLeftMileage": "油续航",
            "leftFuel": "剩余燃油", "voltage": "电压", "lowBatVol": "低压电瓶", "current": "电流",
            "charging": "充电中", "chargePower": "充电功率", "wireConnect": "枪连接",
            "lowBeamLight": "近光", "dipHeadLight": "远光", "leftTurnLight": "左转向",
            "rightTurnLight": "右转向", "positionLight": "位置灯", "frontFogLight": "前雾灯",
            "rearFogLight": "后雾灯", "mileage": "总里程", "vehSpdAvgDrvn": "平均车速",
            "strWhAng": "方向盘", "brakPedalPos": "刹车%", "accActPos": "油门%",
            "latitude": "纬度", "longitude": "经度", "collectTime": "采集时间",
            "sentinelModeStatus": "哨兵", "initialized": "initialized"
        ]

        let dump = allFields.keys.sorted().map { key -> String in
            let star = changedKeys.contains(key) ? "★" : ""
            let label = zhName[key] ?? key
            let val = allFields[key] ?? ""
            let show = val.isEmpty ? "(空)" : val
            return "\(star)\(label)(\(key))=\(show)"
        }.joined(separator: ", ")
        parts.append("全字段：\(dump)")

        // PB wire 级字段号列表（扩 nameMap 用）
        if let pbWireDump, !pbWireDump.isEmpty {
            parts.append("PB字段：\(pbWireDump)")
        }

        // 原始 hex（140B 级完整保留；过大则截断）
        if let rawHex, !rawHex.isEmpty {
            parts.append("rawHex==\(rawHex)")
        }

        // 若有原始 JSON，附上（截断防爆日志；完整可复制前 3500 字）
        if let raw = rawJSON, !raw.isEmpty {
            let maxLen = 3500
            if raw.count <= maxLen {
                parts.append("原始JSON==\(raw)")
            } else {
                let head = String(raw.prefix(maxLen))
                parts.append("原始JSON(截断\(raw.count)字)==\(head)…")
            }
        }

        return parts.joined(separator: " || ")
    }

    /// 把 MQTT 原始字段整理成中文可读快照（只用于事件日志诊断，不改 UI 策略）。
    private func formatMQTTStatusChinese(
        fields: [String: String],
        previous: [String: String],
        changedKeys: Set<String>
    ) -> String {
        func mark(_ key: String) -> String { changedKeys.contains(key) ? "★" : "" }

        func lockText(_ raw: String?) -> String {
            guard let locked = parseLocked(raw) else {
                return raw?.isEmpty == false ? "原始\(raw!)" : "无"
            }
            return locked ? "已锁(0)" : "未锁(1)"
        }
        func openText(_ raw: String?) -> String {
            guard let open = parseOpen(raw) else {
                return raw?.isEmpty == false ? "原始\(raw!)" : "无"
            }
            return open ? "开(1)" : "关(0)"
        }
        func windowText(status: String?, degree: String?, half: String?) -> String {
            if let deg = parseDouble(degree), deg > 0 { return "开(开度\(Int(deg)))" }
            if parseOpen(half) == true { return "半开" }
            return openText(status)
        }
        func acText(_ raw: String?) -> String {
            guard let on = parseACStatus(raw) else {
                return raw?.isEmpty == false ? "原始\(raw!)" : "无"
            }
            // 官方常见：0关 1冷 2热 6开 7关
            let extra = raw.map { "原始\($0)" } ?? ""
            return (on ? "开" : "关") + (extra.isEmpty ? "" : "·\(extra)")
        }
        func keyText(_ raw: String?) -> String {
            switch raw?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "0": return "远离(0)"
            case "1": return "车外(1)"
            case "2": return "车内(2·云端常误报)"
            case "255": return "无效(255)"
            case .some(let v) where !v.isEmpty: return "原始\(v)"
            default: return "无"
            }
        }
        func powerText(_ s: [String: String]) -> String {
            if let p = parsePowerState(s) {
                switch p {
                case .off: return "熄火/下电"
                case .acc: return "ACC"
                case .on: return "已上电"
                case .ready: return "Ready"
                case .unknown: return "未知"
                }
            }
            let eng = s["engineStatus"] ?? ""
            return eng.isEmpty ? "无电源字段(本车 engine 常空)" : "engine=\(eng)"
        }

        let collect = fields["collectTime"].flatMap { $0.isEmpty ? nil : $0 } ?? "无采集时间"
        let fieldCount = fields.count

        // 总览
        var parts: [String] = []
        parts.append("采集时间=\(collect)")
        parts.append("字段数=\(fieldCount)")
        parts.append("总锁\(mark("doorLockStatus"))=\(lockText(fields["doorLockStatus"]))")
        parts.append("总门\(mark("doorOpenStatus"))=\(openText(fields["doorOpenStatus"]))")
        parts.append("总窗\(mark("windowStatus"))=\(openText(fields["windowStatus"]))")
        parts.append("尾门\(mark("tailDoorOpenStatus"))=\(openText(fields["tailDoorOpenStatus"]))")
        parts.append("尾门锁\(mark("tailDoorLockStatus"))=\(lockText(fields["tailDoorLockStatus"]))")
        parts.append("空调\(mark("acStatus"))=\(acText(fields["acStatus"]))")
        if let temp = fields["accCntTemp"], !temp.isEmpty {
            parts.append("设定温度\(mark("accCntTemp"))=\(temp)°C")
        }
        parts.append("钥匙\(mark("keyStatus"))=\(keyText(fields["keyStatus"]))")
        parts.append("电源=\(powerText(fields))")

        // 四门
        let doors = [
            ("主驾门", "door1OpenStatus", "door1LockStatus"),
            ("副驾门", "door2OpenStatus", "door2LockStatus"),
            ("左后门", "door3OpenStatus", "door3LockStatus"),
            ("右后门", "door4OpenStatus", "door4LockStatus")
        ]
        let doorLine = doors.map { name, openKey, lockKey in
            "\(name)\(mark(openKey))=\(openText(fields[openKey]))/\(lockText(fields[lockKey]))"
        }.joined(separator: " · ")
        parts.append("四门[\(doorLine)]")

        // 四窗
        let windows: [(String, String, String, String)] = [
            ("主驾窗", "window1Status", "window1OpenDegree", "window1HalfOpenStatus"),
            ("副驾窗", "window2Status", "window2OpenDegree", "window2HalfOpenStatus"),
            ("左后窗", "window3Status", "window3OpenDegree", "window3HalfOpenStatus"),
            ("右后窗", "window4Status", "window4OpenDegree", "window4HalfOpenStatus")
        ]
        let windowLine = windows.map { name, st, deg, half in
            "\(name)\(mark(st))=\(windowText(status: fields[st], degree: fields[deg], half: fields[half]))"
        }.joined(separator: " · ")
        parts.append("四窗[\(windowLine)]")

        // 变化摘要（中文）
        if !changedKeys.isEmpty {
            let nameMap: [String: String] = [
                "doorLockStatus": "总锁",
                "doorOpenStatus": "总门",
                "door1OpenStatus": "主驾门", "door2OpenStatus": "副驾门",
                "door3OpenStatus": "左后门", "door4OpenStatus": "右后门",
                "door1LockStatus": "主驾锁", "door2LockStatus": "副驾锁",
                "door3LockStatus": "左后锁", "door4LockStatus": "右后锁",
                "tailDoorOpenStatus": "尾门", "tailDoorLockStatus": "尾门锁",
                "windowStatus": "总窗",
                "window1Status": "主驾窗", "window2Status": "副驾窗",
                "window3Status": "左后窗", "window4Status": "右后窗",
                "acStatus": "空调", "accCntTemp": "设定温度",
                "keyStatus": "钥匙位置", "engineStatus": "发动机/电源",
                "batterySoc": "电量", "leftMileage": "续航"
            ]
            let zhChanges: [String] = changedKeys.sorted().prefix(12).map { key in
                let label = nameMap[key] ?? key
                let oldV = previous[key] ?? "?"
                let newV = fields[key] ?? "?"
                // 尽量中文解释新旧值
                let pretty: (String) -> String = { raw in
                    if key.contains("Lock") || key == "doorLockStatus" || key == "tailDoorLockStatus" {
                        return lockText(raw == "?" ? nil : raw)
                    }
                    if key.contains("Open") || key.contains("window") || key == "doorOpenStatus" || key == "windowStatus" {
                        return openText(raw == "?" ? nil : raw)
                    }
                    if key == "acStatus" { return acText(raw == "?" ? nil : raw) }
                    if key == "keyStatus" { return keyText(raw == "?" ? nil : raw) }
                    return raw
                }
                return "\(label) \(pretty(oldV))→\(pretty(newV))"
            }
            parts.append("变化★: " + zhChanges.joined(separator: "；"))
        } else {
            parts.append("变化★: 无（与上次相同）")
        }

        parts.append("说明: MQTT 字段已回写 UI；HTTP 仅补齐/收敛")
        return parts.joined(separator: " | ")
    }

    /// 仅记录与无感/车控无关的 MQTT 变化，避免辅助遥测反复占用整车快照日志。
    /// 业务状态合并、控制确认与 HTTP 补齐在调用处保持原样。
    private func formatMQTTAuxiliaryStatusLog(
        fields: [String: String],
        previous: [String: String],
        changedKeys: Set<String>,
        format: String,
        payloadBytes: Int
    ) -> String {
        let labels: [String: String] = [
            "lowBeamLight": "近光", "dipHeadLight": "远光", "leftTurnLight": "左转向", "rightTurnLight": "右转向",
            "positionLight": "位置灯", "frontFogLight": "前雾灯", "rearFogLight": "后雾灯",
            "batterySoc": "电量", "leftMileage": "电续航", "oilLeftMileage": "油续航", "leftFuel": "燃油",
            "mileage": "总里程", "vehSpdAvgDrvn": "平均车速", "interiorTemperature": "车内温度",
            "strWhAng": "方向盘", "brakPedalPos": "刹车", "accActPos": "油门"
        ]
        let changes = changedKeys.sorted().prefix(10).map { key in
            labels[key] ?? key
        }.joined(separator: "、")
        let extra = changedKeys.count > 10 ? " · 其余\(changedKeys.count - 10)项" : ""
        return "格式=\(format) · payload=\(payloadBytes)B · 辅助变化=\(changes)\(extra) · HTTP补齐"
    }

    /// 默认短日志：日常只看摘要与变化；全字段/PB/rawHex 保留在解码函数，后续需要可再挂详细开关。
    private func formatMQTTStatusShortLog(
        fields: [String: String],
        previous: [String: String],
        changedKeys: Set<String>,
        format: String,
        payloadBytes: Int,
        unmappedFieldNumbers: [Int]
    ) -> String {
        func lockText(_ raw: String?) -> String {
            guard let locked = parseLocked(raw) else { return raw?.isEmpty == false ? raw! : "--" }
            return locked ? "已锁" : "未锁"
        }
        func openText(_ raw: String?, closed: String = "关", open: String = "开") -> String {
            guard let isOpen = parseOpen(raw) else { return raw?.isEmpty == false ? raw! : "--" }
            return isOpen ? open : closed
        }
        func windowsText() -> String {
            if let closed = parseWindowsClosed(fields) { return closed ? "全关" : "未关" }
            return openText(fields["windowStatus"], closed: "全关", open: "未关")
        }
        func doorsText() -> String {
            if let closed = parseDoorClosed(fields) { return closed ? "全关" : "未关" }
            return openText(fields["doorOpenStatus"], closed: "全关", open: "未关")
        }
        func label(_ key: String) -> String {
            [
                "doorLockStatus": "总锁", "door1LockStatus": "主驾锁", "door2LockStatus": "副驾锁",
                "door3LockStatus": "左后锁", "door4LockStatus": "右后锁",
                "doorOpenStatus": "总门", "door1OpenStatus": "主驾门", "door2OpenStatus": "副驾门",
                "door3OpenStatus": "左后门", "door4OpenStatus": "右后门", "tailDoorOpenStatus": "尾门",
                "windowStatus": "总窗", "window1Status": "主驾窗", "window2Status": "副驾窗",
                "window3Status": "左后窗", "window4Status": "右后窗",
                "acStatus": "空调", "accCntTemp": "设温", "lowBeamLight": "近光", "dipHeadLight": "远光",
                "keyStatus": "钥匙", "batterySoc": "电量", "leftMileage": "电续航", "leftFuel": "燃油",
                "charging": "充电", "wireConnect": "插枪", "vecChrgingSts": "充电状态"
            ][key] ?? key
        }
        func pretty(_ key: String, _ raw: String?) -> String {
            if key.contains("Lock") || key == "doorLockStatus" || key == "tailDoorLockStatus" { return lockText(raw) }
            if key.contains("Open") || key.contains("window") || key == "doorOpenStatus" || key == "windowStatus" { return openText(raw) }
            if key == "acStatus" { return parseACStatus(raw).map { $0 ? "开" : "关" } ?? (raw ?? "--") }
            return raw?.isEmpty == false ? raw! : "--"
        }

        let changed = changedKeys.sorted().prefix(10).map { key in
            "\(label(key)):\(pretty(key, previous[key]))→\(pretty(key, fields[key]))"
        }.joined(separator: ", ")
        var parts: [String] = []
        parts.append("格式=\(format) · payload=\(payloadBytes)B · 字段=\(fields.count)")
        if !unmappedFieldNumbers.isEmpty {
            parts.append("未映射=[\(unmappedFieldNumbers.map(String.init).joined(separator: ","))]")
        }
        parts.append("锁=\(lockText(fields["doorLockStatus"])) 门=\(doorsText()) 窗=\(windowsText()) 尾=\(openText(fields["tailDoorOpenStatus"], closed: "已关", open: "已开"))")
        if let temp = fields["accCntTemp"], !temp.isEmpty {
            parts.append("空调=\(parseACStatus(fields["acStatus"]).map { $0 ? "开" : "关" } ?? "--")/\(temp)°C")
        } else if fields["acStatus"] != nil {
            parts.append("空调=\(parseACStatus(fields["acStatus"]).map { $0 ? "开" : "关" } ?? "--")")
        }
        parts.append(changed.isEmpty ? "变化=无（已回写UI）" : "变化=\(changed) · 已回写UI · HTTP补齐")
        return parts.joined(separator: " · ")
    }

    /// `/vehicle/control` 是官方订阅的可选附加回执通道；普通锁/窗主确认仍是 status MQTT / HTTP。
    func handleVehicleControlResult(_ data: Data, topic: String) {
        let result = decodeControlResult(data)
        let diagnostic = formatControlPayloadDiagnostic(data)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mqttStatus = .connected
            if let result {
                self.latestControlResult = result
                self.vehicleEventLogStore.add(
                    result.isSuccess ? .action : .warning,
                    "MQTT Control 附加回执",
                    detail: "topic=\(topic) · \(result.displayDetail) · \(diagnostic)"
                )
            } else {
                self.vehicleEventLogStore.add(
                    .warning,
                    "MQTT Control 未识别包",
                    detail: "topic=\(topic) · \(diagnostic)"
                )
            }
        }
    }

    private func formatControlPayloadDiagnostic(_ data: Data) -> String {
        let decoded = ProtobufDecoder.decode(data)
        let fields = decoded.map { "#\($0.fieldNumber):\(protobufFieldPreview($0))" }.joined(separator: " ")
        let raw = formatMQTTPayloadHex(data)
        if fields.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return "payload=\(data.count)B · text=\(String(text.prefix(800))) · rawHex=\(raw)"
        }
        return "payload=\(data.count)B · PB[\(fields.isEmpty ? "empty" : fields)] · rawHex=\(raw)"
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

    /// MQTT 解码结果：业务用非空字段；日志用全字段 + hex/PB 字段号（扩表诊断）。
    private struct MQTTDecodedPayload {
        /// protobuf / json / protobuf+json / empty
        let format: String
        /// 含空串，尽量完整，供官方风格日志
        let allFields: [String: String]
        /// 仅非空，供合并/变化检测（空串不当有效值）
        let nonEmptyFields: [String: String]
        /// 若 payload 本身是 JSON 文本，保留原文
        let rawJSONText: String?
        /// 原始 payload 十六进制（小包完整；大包截断并标注）
        let rawHex: String?
        /// PB wire 字段摘要：#号:wire=值
        let pbWireDump: String?
        /// nameMap 未覆盖的字段号（>21 或未知）
        let unmappedFieldNumbers: [Int]
    }

    /// SgmwAppCarStatus 完整字段（官方 LingLingBang 二进制 GPB descriptor，1…82）
    /// 来源：安装包 `+[SgmwAppCarStatus descriptor]` → fields 表 0x1021b8b68
    /// 注意：旧 nameMap 1…21 错误（把分锁号当成门开），会导致解锁「假开门」。
    private static let mqttProtobufNameMap: [Int: String] = [
        1: "collectTime",
        2: "acStatus",
        3: "doorLockStatus",
        4: "windowStatus",
        5: "engineStatus",
        6: "tailDoorLockStatus",
        7: "lowBeamLight",
        8: "dipHeadLight",
        9: "sentinelModeStatus",
        10: "tailDoorOpenStatus",
        11: "door1LockStatus",
        12: "door2LockStatus",
        13: "door3LockStatus",
        14: "door4LockStatus",
        15: "doorOpenStatus",
        16: "door1OpenStatus",
        17: "door2OpenStatus",
        18: "door3OpenStatus",
        19: "door4OpenStatus",
        20: "window1Status",
        21: "window2Status",
        22: "window3Status",
        23: "window4Status",
        24: "topWindowStatus",
        25: "autoGearStatus",
        26: "manualGearStatus",
        27: "keyStatus",
        28: "acTemperatureGear",
        29: "acWindGear",
        30: "leftBatteryPower",
        31: "leftFuel",
        32: "mileage",
        33: "leftMileage",
        34: "batterySoc",
        35: "current",
        36: "voltage",
        37: "batAvgTemp",
        38: "batMaxTemp",
        39: "batMinTemp",
        40: "tmActTemp",
        41: "invActTemp",
        42: "accActPos",
        43: "brakPedalPos",
        44: "strWhAng",
        45: "vehSpdAvgDrvn",
        46: "obcOtpCur",
        47: "vecChrgingSts",
        48: "vecChrgStsIndOn",
        49: "obcTemp",
        50: "batSoh",
        51: "lowBatVol",
        52: "leftTurnLight",
        53: "rightTurnLight",
        54: "positionLight",
        55: "frontFogLight",
        56: "rearFogLight",
        57: "latitude",
        58: "longitude",
        59: "position",
        60: "charging",
        61: "wireConnect",
        62: "rechargeStatus",
        63: "window1OpenDegree",
        64: "window2OpenDegree",
        65: "window3OpenDegree",
        66: "window4OpenDegree",
        67: "seat1WindStatus",
        68: "seat2WindStatus",
        69: "seat3WindStatus",
        70: "seat4WindStatus",
        71: "seat1HotStatus",
        72: "seat2HotStatus",
        73: "seat3HotStatus",
        74: "seat4HotStatus",
        75: "accCntTemp",
        76: "leftSlidingDoorStatus",
        77: "rightSlidingDoorStatus",
        78: "windowHalfOpenStatus",
        79: "window1HalfOpenStatus",
        80: "window2HalfOpenStatus",
        81: "window3HalfOpenStatus",
        82: "window4HalfOpenStatus"
    ]

    private func decodeMQTTPayload(_ data: Data) -> MQTTDecodedPayload {
        let pbDecoded = decodeProtobufMQTTDetailed(data)
        let (jsonAll, jsonRaw) = decodeJSONMQTTFieldsDetailed(data)

        // JSON 与 PB 都解：合并后 JSON 覆盖同名（更接近官方完整包）
        var all: [String: String] = pbDecoded.namedFields
        for (k, v) in jsonAll {
            all[k] = v
        }
        let format: String = {
            if jsonAll.isEmpty && pbDecoded.namedFields.isEmpty { return "empty" }
            if pbDecoded.namedFields.isEmpty { return "json" }
            if jsonAll.isEmpty { return "protobuf" }
            if jsonAll.count > pbDecoded.namedFields.count { return "json>protobuf" }
            if pbDecoded.namedFields.count > jsonAll.count { return "protobuf>json" }
            return "json+protobuf"
        }()

        var nonEmpty: [String: String] = [:]
        for (k, v) in all where !v.isEmpty {
            nonEmpty[k] = v
        }

        let raw: String?
        if let jsonRaw, !jsonRaw.isEmpty {
            raw = jsonRaw
        } else if format.contains("json"), let rebuilt = encodeFieldsAsJSONObject(all) {
            raw = rebuilt
        } else {
            raw = nil
        }

        return MQTTDecodedPayload(
            format: format,
            allFields: all,
            nonEmptyFields: nonEmpty,
            rawJSONText: raw,
            rawHex: formatMQTTPayloadHex(data),
            pbWireDump: pbDecoded.wireDump.isEmpty ? nil : pbDecoded.wireDump,
            unmappedFieldNumbers: pbDecoded.unmappedFieldNumbers
        )
    }

    private struct MQTTProtobufDecodeDetail {
        let namedFields: [String: String]
        let wireDump: String
        let unmappedFieldNumbers: [Int]
    }

    private func decodeProtobufMQTTDetailed(_ data: Data) -> MQTTProtobufDecodeDetail {
        let decoded = ProtobufDecoder.decode(data)
        let nameMap = Self.mqttProtobufNameMap
        var result: [String: String] = [:]
        var wireParts: [String] = []
        var unmapped: [Int] = []
        var seenUnmapped = Set<Int>()

        for field in decoded {
            let preview = protobufFieldPreview(field)
            if let name = nameMap[field.fieldNumber] {
                wireParts.append("#\(field.fieldNumber)(\(name)):\(preview)")
                switch field.wireType {
                case .varint:
                    if let val = ProtobufDecoder.int64(field) { result[name] = String(val) }
                case .lengthDelimited:
                    if let val = ProtobufDecoder.string(field) {
                        result[name] = val
                    } else {
                        // 非 UTF-8 字符串：仍记 hex 片段，便于对照
                        result[name] = "hex:\(field.data.map { String(format: "%02x", $0) }.joined())"
                    }
                case .fixed64, .fixed32:
                    result[name] = preview
                }
            } else {
                wireParts.append("#\(field.fieldNumber)(?):\(preview)")
                if seenUnmapped.insert(field.fieldNumber).inserted {
                    unmapped.append(field.fieldNumber)
                }
            }
        }
        unmapped.sort()
        return MQTTProtobufDecodeDetail(
            namedFields: result,
            wireDump: wireParts.joined(separator: " "),
            unmappedFieldNumbers: unmapped
        )
    }

    private func protobufFieldPreview(_ field: ProtobufField) -> String {
        switch field.wireType {
        case .varint:
            if let val = ProtobufDecoder.int64(field) { return "varint=\(val)" }
            return "varint=?"
        case .lengthDelimited:
            if let s = ProtobufDecoder.string(field) {
                let shown = s.count > 48 ? String(s.prefix(48)) + "…" : s
                return "str=\"\(shown)\""
            }
            let hex = field.data.prefix(24).map { String(format: "%02x", $0) }.joined()
            let more = field.data.count > 24 ? "…" : ""
            return "bytes[\(field.data.count)]=\(hex)\(more)"
        case .fixed64:
            return "fixed64"
        case .fixed32:
            return "fixed32"
        }
    }

    /// 原始 payload hex：≤256B 全打；更大打前 256B 并标注总长
    private func formatMQTTPayloadHex(_ data: Data) -> String {
        let limit = 256
        if data.count <= limit {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        let head = data.prefix(limit).map { String(format: "%02x", $0) }.joined()
        return "\(head)…(total \(data.count)B)"
    }

    private func decodeProtobufMQTTFields(_ data: Data) -> [String: String] {
        decodeProtobufMQTTDetailed(data).namedFields
    }

    /// 返回 (全字段含空串, 原始 JSON 文本)
    private func decodeJSONMQTTFieldsDetailed(_ data: Data) -> ([String: String], String?) {
        // 先尝试 UTF-8 文本（官方日志链路即 JSON 文本）
        let rawText = String(data: data, encoding: .utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return ([:], nil)
        }
        guard let dict = json as? [String: Any] else {
            return ([:], rawText)
        }
        let source = (dict["data"] as? [String: Any])
            ?? (dict["carStatus"] as? [String: Any])
            ?? dict
        var result: [String: String] = [:]
        for (k, v) in source {
            switch v {
            case let s as String:
                // 保留空串，便于官方风格「全字段」日志
                result[k] = s
            case let n as NSNumber:
                // Bool 桥成 NSNumber 时 stringValue 多为 0/1；统一用 stringValue
                result[k] = n.stringValue
            case let b as Bool:
                result[k] = b ? "1" : "0"
            case is NSNull:
                result[k] = ""
            default:
                // 嵌套对象：压成短 JSON，避免丢键
                if let nested = try? JSONSerialization.data(withJSONObject: v, options: []),
                   let s = String(data: nested, encoding: .utf8) {
                    result[k] = s
                }
            }
        }
        // 优先用原始文本；否则 pretty 再序列化 source
        let rawOut: String?
        if let rawText, rawText.first == "{" || rawText.first == "[" {
            rawOut = rawText
        } else if let pretty = try? JSONSerialization.data(withJSONObject: source, options: [.sortedKeys]),
                  let s = String(data: pretty, encoding: .utf8) {
            rawOut = s
        } else {
            rawOut = rawText
        }
        return (result, rawOut)
    }

    private func encodeFieldsAsJSONObject(_ fields: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    /// 兼容旧调用名
    private func decodeMQTTFields(_ data: Data) -> [String: String] {
        decodeMQTTPayload(data).nonEmptyFields
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
            handleVehicleControlResult(payload, topic: message.topic)
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
