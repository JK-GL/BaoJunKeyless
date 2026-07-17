import Foundation

enum VehicleHTTPMergeMode: String {
    /// 手动刷新：强制全量落地
    case full = "全量"
    /// 自动轮询：HTTP 完整权威快照
    case pollFull = "轮询全量"
    /// 兼容旧内部分支；新主链不再选择此模式。
    case pollMeta = "轮询元信息"
}

extension MQTTVehicleStateStore {
    /// BLE 本地锁/解锁后，网络门锁短保护
    static let localLockHoldSeconds: TimeInterval = 15

    /// 状态主链：
    /// - HTTP：完整权威快照，自动/手动刷新都全量落地
    /// - MQTT：仅提示变化并唤醒 HTTP，不参与本函数覆盖
    /// - HTTP 只与上一次 HTTP collectTime 比较，避免 MQTT 半包卡住完整快照
    /// - 总览由四门四窗明细重算
    @discardableResult
    func mergeHTTPBaseState(
        newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        mode: VehicleHTTPMergeMode = .full,
        httpCollectAt: Date? = nil,
        sourceFields: [String: String] = [:]
    ) -> String {
        let collectAt = httpCollectAt ?? Date()
        let now = Date()

        // HTTP 只与上一次已采纳的 HTTP 快照比较；MQTT 时间绝不能挡住 HTTP 全量。
        if let current = lastHTTPBodyCollectAt, collectAt < current {
            return "丢弃旧HTTP"
        }

        // HTTP 完整快照带来的未锁→已锁，若不是本 App 近期命令，视为外部/物理锁车。
        if sourceFields["doorLockStatus"] != nil {
            observeAuthoritativeLockState(newState.locked)
        }

        // MQTT 在线新鲜：HTTP 不冲门窗/锁等实时车身，但补齐 MQTT Protobuf 常缺的字段
        // （电量/续航/充电/电源/档位/胎压/温度等）——MQTT 主实时 + HTTP 补全
        if mode == .pollMeta {
            lastHTTPBodyCollectAt = collectAt
            var dash = dashboard
            var st = state
            var changed = false

            func takeText(_ current: String, _ incoming: String) -> String {
                let n = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
                if n.isEmpty || n == "--" { return current }
                if current != n { changed = true }
                return n
            }
            func takeOptText(_ current: String, _ incoming: String, onlyIfEmpty: Bool = false) -> String {
                let n = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
                if n.isEmpty || n == "--" { return current }
                if onlyIfEmpty {
                    let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !c.isEmpty && c != "--" { return current }
                }
                if current != n { changed = true }
                return n
            }

            // 电源/档位：上电状态对齐远程启动按钮
            if newState.power != .unknown, st.power != newState.power {
                st.power = newState.power
                changed = true
            }
            if newState.gear != .unknown, st.gear != newState.gear {
                st.gear = newState.gear
                changed = true
            }
            if let v = newState.fuelLevel, st.fuelLevel != v { st.fuelLevel = v; changed = true }
            if let v = newState.fuelRange, st.fuelRange != v { st.fuelRange = v; changed = true }
            if let v = newState.oilRange, st.oilRange != v { st.oilRange = v; changed = true }
            if let v = newState.speed, st.speed != v { st.speed = v; changed = true }
            // keyStatus：仍更新模型；显示层继续走防误报规则
            if newState.physicalKeyPosition != .unknown, st.physicalKeyPosition != newState.physicalKeyPosition {
                st.physicalKeyPosition = newState.physicalKeyPosition
                changed = true
            }

            // 仪表/充电/温度/胎压（非门窗锁）
            // batteryPercentValue / fuelPercentValue 为 Optional；里程字段为非 Optional Int
            if let v = newDashboard.batteryPercentValue, dash.batteryPercentValue != v {
                dash.batteryPercentValue = v
                changed = true
            }
            if newDashboard.electricRangeKm > 0, dash.electricRangeKm != newDashboard.electricRangeKm {
                dash.electricRangeKm = newDashboard.electricRangeKm
                changed = true
            }
            if newDashboard.fuelRangeKm > 0, dash.fuelRangeKm != newDashboard.fuelRangeKm {
                dash.fuelRangeKm = newDashboard.fuelRangeKm
                changed = true
            }
            if let v = newDashboard.fuelPercentValue, dash.fuelPercentValue != v {
                dash.fuelPercentValue = v
                changed = true
            }
            dash.batteryRemainingText = takeText(dash.batteryRemainingText, newDashboard.batteryRemainingText)
            dash.batteryHealthPercentText = takeText(dash.batteryHealthPercentText, newDashboard.batteryHealthPercentText)
            dash.batteryVoltageText = takeText(dash.batteryVoltageText, newDashboard.batteryVoltageText)
            dash.batteryAuxText = takeText(dash.batteryAuxText, newDashboard.batteryAuxText)
            dash.cabinTemperatureText = takeText(dash.cabinTemperatureText, newDashboard.cabinTemperatureText)
            dash.batteryTemperatureText = takeText(dash.batteryTemperatureText, newDashboard.batteryTemperatureText)
            dash.motorTemperatureText = takeText(dash.motorTemperatureText, newDashboard.motorTemperatureText)
            dash.inverterTemperatureText = takeText(dash.inverterTemperatureText, newDashboard.inverterTemperatureText)
            if dash.isCharging != newDashboard.isCharging { dash.isCharging = newDashboard.isCharging; changed = true }
            dash.chargingStatusText = takeText(dash.chargingStatusText, newDashboard.chargingStatusText)
            dash.chargingPowerText = takeText(dash.chargingPowerText, newDashboard.chargingPowerText)
            dash.chargingPowerValueText = takeText(dash.chargingPowerValueText, newDashboard.chargingPowerValueText)
            dash.obcCurrentText = takeText(dash.obcCurrentText, newDashboard.obcCurrentText)
            dash.obcTemperatureText = takeText(dash.obcTemperatureText, newDashboard.obcTemperatureText)
            dash.chargingStateText = takeText(dash.chargingStateText, newDashboard.chargingStateText)
            dash.totalMileageText = takeText(dash.totalMileageText, newDashboard.totalMileageText)
            dash.yesterdayMileageText = takeText(dash.yesterdayMileageText, newDashboard.yesterdayMileageText)
            dash.averageFuelConsumptionText = takeText(dash.averageFuelConsumptionText, newDashboard.averageFuelConsumptionText)
            dash.averagePowerConsumptionText = takeText(dash.averagePowerConsumptionText, newDashboard.averagePowerConsumptionText)
            dash.steeringAngleText = takeText(dash.steeringAngleText, newDashboard.steeringAngleText)
            dash.throttlePercentText = takeText(dash.throttlePercentText, newDashboard.throttlePercentText)
            dash.brakePercentText = takeText(dash.brakePercentText, newDashboard.brakePercentText)
            // 空调：
            // - 开关：若 MQTT 更新且比本包 HTTP collect 新，不让旧 HTTP 把开关冲回（避免连跳）
            // - 温度：始终接受 HTTP accCntTemp（当前 MQTT protobuf 通常不带温度）
            let mqttClimateFresher = lastMQTTClimateAt.map { $0 > collectAt } ?? false
            if !mqttClimateFresher, let ac = newState.acOn, st.acOn != ac {
                st.acOn = ac
                changed = true
            }
            if let t = newState.acTemperature, st.acTemperature != t {
                st.acTemperature = t
                changed = true
            }
            // 文案优先用温度；没有温度时再跟开关态
            if let t = st.acTemperature {
                let text = "\(Int(t.rounded()))°C"
                if dash.acTemperatureText != text {
                    dash.acTemperatureText = text
                    changed = true
                }
            } else if !mqttClimateFresher {
                dash.acTemperatureText = takeText(dash.acTemperatureText, newDashboard.acTemperatureText)
            }

            dash.leftFrontTirePressureText = takeOptText(dash.leftFrontTirePressureText, newDashboard.leftFrontTirePressureText)
            dash.rightFrontTirePressureText = takeOptText(dash.rightFrontTirePressureText, newDashboard.rightFrontTirePressureText)
            dash.leftRearTirePressureText = takeOptText(dash.leftRearTirePressureText, newDashboard.leftRearTirePressureText)
            dash.rightRearTirePressureText = takeOptText(dash.rightRearTirePressureText, newDashboard.rightRearTirePressureText)
            dash.tireTemperatureText = takeOptText(dash.tireTemperatureText, newDashboard.tireTemperatureText)

            // 灯光等（若 HTTP 有）
            dash.lowBeamText = takeText(dash.lowBeamText, newDashboard.lowBeamText)
            dash.highBeamText = takeText(dash.highBeamText, newDashboard.highBeamText)
            dash.leftTurnText = takeText(dash.leftTurnText, newDashboard.leftTurnText)
            dash.rightTurnText = takeText(dash.rightTurnText, newDashboard.rightTurnText)
            dash.positionLightText = takeText(dash.positionLightText, newDashboard.positionLightText)
            dash.frontFogText = takeText(dash.frontFogText, newDashboard.frontFogText)

            // 门窗/尾门：MQTT 半包常在解锁时夹带假开门。
            // HTTP 全量明细是权威；MQTT 新鲜时也允许 HTTP 纠正门窗开闭。
            // 门锁：BLE 本地保护窗外，允许 HTTP 纠正。
            let bodyCorrected = applyHTTPDoorWindowAuthority(
                onto: &dash,
                state: &st,
                from: newDashboard,
                newState: newState,
                sourceFields: sourceFields
            )
            if bodyCorrected { changed = true }

            let lockProtected = localDoorLockHoldUntil.map { now < $0 } ?? false
            if !lockProtected, sourceFields["doorLockStatus"] != nil {
                if let locked = newState.locked, st.locked != locked {
                    st.locked = locked
                    changed = true
                }
                let lockText = newDashboard.lockStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !lockText.isEmpty, lockText != "--", dash.lockStatusText != lockText {
                    dash.lockStatusText = lockText
                    changed = true
                }
            }

            if changed {
                dash.updatedAt = max(dash.updatedAt, collectAt, now)
                dash.updatedAtText = formatTime(dash.updatedAt)
                st.timestamp = max(st.timestamp, collectAt, now)
                st.online = true
                // 总览只信明细
                dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
                dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)
                syncBooleans(from: dash, into: &st)
                // 不推进 bodyCollectTime，避免挡住随后真实 MQTT 门窗变化
                bumpStatusRevision()
                st = applyLiveBLEOverlay(to: st)
                apply(st)
                applyDashboard(dash)
                evaluateKeylessAutomation(for: st)
                return bodyCorrected ? "轮询元信息+门窗纠正/MQTT新鲜" : "轮询元信息补齐/MQTT新鲜"
            }
            return "轮询元信息/MQTT新鲜"
        }

        var dash = Self.stripDashboardBodyCacheSuffix(newDashboard)
        // 总览强制由明细重算，禁止总字段误伤
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)

        // BLE 本地锁保护窗内，不覆盖门锁。
        // 空调开关：MQTT 更新时不被更旧 HTTP 冲回；温度始终允许 HTTP 更新。
        var mergedState = newState
        if let until = localDoorLockHoldUntil, now < until {
            mergedState.locked = state.locked
            dash.lockStatusText = dashboard.lockStatusText
        }
        let mqttClimateFresher = lastMQTTClimateAt.map { $0 > collectAt } ?? false
        if mqttClimateFresher {
            mergedState.acOn = state.acOn
            // 若本包 HTTP 没带有效温度，才保留当前温度；有 accCntTemp 则用 HTTP。
            if newState.acTemperature == nil {
                mergedState.acTemperature = state.acTemperature
                dash.acTemperatureText = dashboard.acTemperatureText
            } else if let t = newState.acTemperature {
                dash.acTemperatureText = "\(Int(t.rounded()))°C"
            }
        }

        // HTTP 若带明确电源字段则直接确认；若本车型 HTTP 不带，则短时保留最近的
        // MQTT engineStatus / BLE 成功回包，超时后回到未知，避免永久显示陈旧状态。
        if mergedState.power != .unknown {
            lastExplicitPowerStateAt = now
            lastExplicitPowerStateSource = "HTTP电源字段"
        } else if let confirmedAt = lastExplicitPowerStateAt,
                  now.timeIntervalSince(confirmedAt) <= Self.explicitPowerStateHoldSeconds,
                  state.power != .unknown {
            mergedState.power = state.power
        } else {
            lastExplicitPowerStateAt = nil
            lastExplicitPowerStateSource = nil
        }

        var merged = VehicleStateMerger.mergeHTTPBase(current: state, newState: mergedState)
        // 明细权威：用 dashboard 回写布尔
        syncBooleans(from: dash, into: &merged)
        merged.online = true
        // 新鲜度表示本次 HTTP 成功确认时间；collectTime 只用于 HTTP 包的新旧排序。
        merged.timestamp = now

        dash.updatedAt = collectAt
        dash.updatedAtText = formatTime(collectAt)
        bodyCollectTime = collectAt
        lastHTTPBodyCollectAt = collectAt

        // 全量落地后，清理字段保护痕迹（不再用字段戳卡 HTTP）
        fieldCollectAt.removeAll()
        fieldSource.removeAll()
        // 仅保留 BLE 本地锁戳
        if let until = localDoorLockHoldUntil, now < until {
            fieldCollectAt["doorLockStatus"] = now
            fieldSource["doorLockStatus"] = "BLE"
        }

        merged = applyLiveBLEOverlay(to: merged)
        // 同值 HTTP 全量不再 bump/整页刷新；仅时间戳推进。
        let changed = applyVehicleSnapshot(state: merged, dashboard: dash, bumpIfChanged: true)
        if changed {
            evaluateKeylessAutomation(for: merged)
        }

        if mode == .full {
            if !changed {
                return localDoorLockHoldUntil.map { now < $0 ? "手动全量无变化/本地锁保护中" : "手动全量无变化" } ?? "手动全量无变化"
            }
            return localDoorLockHoldUntil.map { now < $0 ? "手动全量/本地锁保护中" : "手动全量" } ?? "手动全量"
        }
        if !changed {
            return localDoorLockHoldUntil.map { now < $0 ? "轮询全量无变化/本地锁保护中" : "轮询全量无变化" } ?? "轮询全量无变化"
        }
        return localDoorLockHoldUntil.map { now < $0 ? "轮询全量/本地锁保护中" : "轮询全量" } ?? "轮询全量"
    }

    /// MQTT 半包：只更新本包出现的字段；总览由明细重算
    func mergeRealtimeState(
        newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        sourceFields: [String: String] = [:],
        collectAt: Date? = nil,
        changedKeys: Set<String> = []
    ) {
        let at = collectAt ?? parseTimestamp(sourceFields["collectTime"]) ?? Date()
        let now = Date()

        // 若 MQTT collectTime 明显旧于当前模型，丢弃（防止旧半包回放）
        if let current = bodyCollectTime, at + 0.5 < current {
            return
        }

        if sourceFields["doorLockStatus"] != nil {
            observeAuthoritativeLockState(newState.locked)
        }

        var safeState = newState
        var safeDash = newDashboard
        if let until = localDoorLockHoldUntil, now < until {
            safeState.locked = nil
            safeDash.lockStatusText = "--"
        }

        // mergeRealtime* 已是“有值才覆盖”
        let mergedBase = VehicleStateMerger.mergeRealtime(current: state, newState: safeState)
        var dash = VehicleStateMerger.mergeRealtimeDashboard(current: dashboard, newDashboard: safeDash)
        dash = Self.stripDashboardBodyCacheSuffix(dash)
        // 关键：总览只由明细重算，绝不让半包总字段把门2/3/4刷开
        dash.doorStatusText = VehicleStatusMapper.recomputeDoorStatusText(from: dash)
        dash.windowStatusText = VehicleStatusMapper.recomputeWindowStatusText(from: dash)
        dash.updatedAt = max(dash.updatedAt, at, now)
        dash.updatedAtText = formatTime(dash.updatedAt)

        var merged = applyLiveBLEOverlay(to: mergedBase)
        syncBooleans(from: dash, into: &merged)
        bodyCollectTime = max(bodyCollectTime ?? at, at)
        lastMQTTBodyCollectAt = at

        // 仅记录变化字段来源（日志用），不再用于卡 HTTP
        for key in changedKeys where sourceFields[key] != nil && key != "collectTime" {
            fieldCollectAt[key] = at
            fieldSource[key] = "MQTT"
        }

        bumpStatusRevision()
        apply(merged)
        applyDashboard(dash)
        evaluateKeylessAutomation(for: merged)
    }

    private func syncBooleans(from dash: VehicleDashboardState, into merged: inout VehicleState) {
        if dash.doorStatusText == "全关" || dash.doorStatusText.hasPrefix("全关") { merged.doorsClosed = true }
        else if dash.doorStatusText == "未关" || dash.doorStatusText.hasPrefix("未关") { merged.doorsClosed = false }
        if dash.windowStatusText == "全关" || dash.windowStatusText.hasPrefix("全关") { merged.windowsClosed = true }
        else if dash.windowStatusText == "未关" || dash.windowStatusText.hasPrefix("未关") { merged.windowsClosed = false }
        if dash.tailgateStatusText == "已关" || dash.tailgateStatusText.hasPrefix("已关") { merged.trunkOpen = false }
        else if dash.tailgateStatusText == "已开" || dash.tailgateStatusText.hasPrefix("已开") { merged.trunkOpen = true }
        if dash.driverDoorStatusText == "已关" || dash.driverDoorStatusText.hasPrefix("已关") { merged.driverDoorOpen = false }
        else if dash.driverDoorStatusText == "未关" || dash.driverDoorStatusText.hasPrefix("未关") { merged.driverDoorOpen = true }
        if dash.lockStatusText == "已锁车" || dash.lockStatusText.hasPrefix("已锁") { merged.locked = true }
        else if dash.lockStatusText == "未锁" || dash.lockStatusText.hasPrefix("未锁") { merged.locked = false }
    }

    /// HTTP 全量门窗明细纠正 MQTT 假半包
    @discardableResult
    private func applyHTTPDoorWindowAuthority(
        onto dash: inout VehicleDashboardState,
        state st: inout VehicleState,
        from newDashboard: VehicleDashboardState,
        newState: VehicleState,
        sourceFields: [String: String]
    ) -> Bool {
        var changed = false

        func takeDetail(_ current: String, _ incoming: String) -> String {
            let n = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty || n == "--" { return current }
            if current != n { changed = true }
            return n
        }

        if sourceFields["door1OpenStatus"] != nil {
            dash.driverDoorStatusText = takeDetail(dash.driverDoorStatusText, newDashboard.driverDoorStatusText)
        }
        if sourceFields["door2OpenStatus"] != nil {
            dash.passengerDoorStatusText = takeDetail(dash.passengerDoorStatusText, newDashboard.passengerDoorStatusText)
        }
        if sourceFields["door3OpenStatus"] != nil {
            dash.leftRearDoorStatusText = takeDetail(dash.leftRearDoorStatusText, newDashboard.leftRearDoorStatusText)
        }
        if sourceFields["door4OpenStatus"] != nil {
            dash.rightRearDoorStatusText = takeDetail(dash.rightRearDoorStatusText, newDashboard.rightRearDoorStatusText)
        }
        if sourceFields["tailDoorOpenStatus"] != nil {
            dash.tailgateStatusText = takeDetail(dash.tailgateStatusText, newDashboard.tailgateStatusText)
        }
        if sourceFields["window1Status"] != nil || sourceFields["window1OpenDegree"] != nil || sourceFields["window1HalfOpenStatus"] != nil {
            dash.leftFrontWindowStatusText = takeDetail(dash.leftFrontWindowStatusText, newDashboard.leftFrontWindowStatusText)
        }
        if sourceFields["window2Status"] != nil || sourceFields["window2OpenDegree"] != nil || sourceFields["window2HalfOpenStatus"] != nil {
            dash.rightFrontWindowStatusText = takeDetail(dash.rightFrontWindowStatusText, newDashboard.rightFrontWindowStatusText)
        }
        if sourceFields["window3Status"] != nil || sourceFields["window3OpenDegree"] != nil || sourceFields["window3HalfOpenStatus"] != nil {
            dash.leftRearWindowStatusText = takeDetail(dash.leftRearWindowStatusText, newDashboard.leftRearWindowStatusText)
        }
        if sourceFields["window4Status"] != nil || sourceFields["window4OpenDegree"] != nil || sourceFields["window4HalfOpenStatus"] != nil {
            dash.rightRearWindowStatusText = takeDetail(dash.rightRearWindowStatusText, newDashboard.rightRearWindowStatusText)
        }

        if let doorsClosed = newState.doorsClosed, st.doorsClosed != doorsClosed {
            st.doorsClosed = doorsClosed
            changed = true
        }
        if let windowsClosed = newState.windowsClosed, st.windowsClosed != windowsClosed {
            st.windowsClosed = windowsClosed
            changed = true
        }
        if let trunkOpen = newState.trunkOpen, st.trunkOpen != trunkOpen {
            st.trunkOpen = trunkOpen
            changed = true
        }
        if let driverOpen = newState.driverDoorOpen, st.driverDoorOpen != driverOpen {
            st.driverDoorOpen = driverOpen
            changed = true
        }

        // 同步 lastMqttFields，避免后续半包继续用假开门做 diff
        for key in Self.doorWindowOpenFieldKeys {
            if let value = sourceFields[key], !value.isEmpty {
                lastMqttFields[key] = value
            }
        }
        return changed
    }

    static let bodyFieldKeys: [String] = [
        "doorLockStatus", "doorOpenStatus",
        "door1OpenStatus", "door2OpenStatus", "door3OpenStatus", "door4OpenStatus", "tailDoorOpenStatus",
        "windowStatus", "window1Status", "window2Status", "window3Status", "window4Status",
        "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
        "acStatus", "batterySoc", "leftMileage", "oilLeftMileage", "mileage", "avgFuel",
        "charging", "chargePower", "interiorTemperature", "keyStatus", "autoGearStatus", "engineStatus",
        "strWhAng", "accActPos", "brakPedalPos", "vehSpd", "speed"
    ]

    func applyHTTPMeta(carInfo: [String: String], carStatus: [String: String]) {
        if let coordinate = VehicleHTTPMetaMapper.coordinate(from: carStatus) {
            liveLatitudeGcj = coordinate.latGcj
            liveLongitudeGcj = coordinate.lngGcj
            cachedLatitudeGcj = coordinate.latGcj
            cachedLongitudeGcj = coordinate.lngGcj
            if let addressHint = coordinate.addressHint, !addressHint.isEmpty {
                liveAddress = addressHint
                cachedAddress = addressHint
                persistDisplayCache()
            } else {
                persistDisplayCache()
            }
            locationResolver.getAddress(gcjLat: coordinate.latGcj, gcjLng: coordinate.lngGcj, address: coordinate.addressHint, amapWebKey: addressSettings.amapWebKey) { [weak self] resolved in
                guard let self, let resolved else { return }
                DispatchQueue.main.async {
                    self.liveAddress = resolved
                    self.cachedAddress = resolved
                    self.persistDisplayCache()
                }
            }
        }

        let dash = VehicleHTTPMetaMapper.dashboard(base: dashboard, carInfo: carInfo)
        if VehicleHTTPMetaMapper.supportsMQTT(carInfo: carInfo) {
            authStatus = .valid
        }
        applyDashboard(dash)

        let profile = VehicleHTTPMetaMapper.profile(carInfo: carInfo, carStatus: carStatus)
        applyProfile(profile)
    }
}
