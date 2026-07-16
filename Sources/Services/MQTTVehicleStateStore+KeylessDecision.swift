import Foundation

extension MQTTVehicleStateStore {
    func resetKeylessRuntimeState() {
        lastUnlockDecision = nil
        lastLockDecision = nil
        lastEvalLocked = nil
        lastEvalNearby = nil
        lastEvalFarAway = nil
        lastEvalInVehicleZone = nil
        phoneNearbySince = nil
        phoneFarAwaySince = nil
        hasEnteredVehicleZone = false
        continuousWeakSince = nil
        bleScanStartedAt = nil
        hasCompletedBLEAuth = false
        userManuallyStoppedBLE = false
        didLogManualForegroundSkip = false
        lastBLEWaitCommandKind = nil
        keylessRejectedActionUntilExit = nil
        externalLockRequiresExit = false
        externalLockExitObserved = false
        expectedAppLockState = nil
        expectedAppLockStateUntil = nil
        resetBLEDiagnosticCycle()
        resetNearbyBLEDevices()
        bleSignalLossWorkItem?.cancel()
        bleSignalLossWorkItem = nil
        isExecutingKeylessCommand = false
    }

    func applyLiveBLEOverlay(to baseState: VehicleState) -> VehicleState {
        guard let rssi = liveBLERSSI else {
            var next = baseState
            next.bleRssi = nil
            // 信号空洞：鉴权中/已进车区时保留靠近语义，避免被当成离开而上锁
            let keepNear = hasCompletedBLEAuth || hasEnteredVehicleZone || bleStatus == .authenticated
            if !keepNear {
                next.phoneNearby = false
            }
            return next
        }
        var next = baseState
        next.bleRssi = rssi
        next.phoneNearby = resolvedPhoneNearby(for: rssi, previous: baseState.phoneNearby)
        return next
    }

    func resolvedPhoneNearby(for smoothedRSSI: Int, previous: Bool) -> Bool {
        if previous {
            return Double(smoothedRSSI) > keylessSettingsStore.settings.lockThreshold
        }
        return Double(smoothedRSSI) >= keylessSettingsStore.settings.unlockThreshold
    }

    func scheduleBLESignalLossTimeout() {
        bleSignalLossWorkItem?.cancel()
        // 坐车内 RSSI 偶发读失败很常见；3s 太短会误判远离→自动上锁
        // 最近还是强信号时更宽；弱信号时稍短
        let last = liveBLERSSI ?? liveBLERawRSSI
        let unlockTh = keylessSettingsStore.settings.unlockThreshold
        let wasStrong = last.map { Double($0) >= unlockTh } ?? false
        let timeout: TimeInterval = wasStrong ? 12.0 : 8.0
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 信号丢失 ≠ 离开。无论是否鉴权，都不因空洞直接上锁。
            // 真正离开只能靠连续真实弱 RSSI。
            let keepZone = self.hasCompletedBLEAuth || self.hasEnteredVehicleZone || self.bleStatus == .authenticated || self.state.phoneNearby
            self.liveBLERawRSSI = nil
            self.liveBLERSSI = nil
            self.liveBLELastSeenAt = nil
            self.debugBLERawRSSI = nil
            self.debugBLESmoothedRSSI = nil
            self.bleDiagnosticsStore.isPreviewRSSI = false
            self.debugBLELastSeenText = "--"
            self.debugBLELastTransitionText = "BLE信号中断 · \(formatTime(Date()))"
            self.continuousWeakSince = nil
            self.phoneFarAwaySince = nil
            self.logVehicleEvent(
                .warning,
                "BLE信号中断",
                detail: keepZone
                    ? "连续 \(Int(timeout))s 无 RSSI，保留车区语义（禁止据此上锁）"
                    : "连续 \(Int(timeout))s 无 RSSI，暂停靠近判定",
                identity: "signal-loss",
                minimumInterval: 8
            )

            var next = self.state
            next.bleRssi = nil
            if !keepZone {
                next.phoneNearby = false
            }
            // 不 evaluate 上锁：空洞不能推进离开
            if next != self.state {
                self.apply(next)
            }
        }
        bleSignalLossWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func applyLiveBLERSSI(_ rawRSSI: Int?) {
        guard let rawRSSI else {
            liveBLERawRSSI = nil
            liveBLERSSI = nil
            liveBLELastSeenAt = nil
            debugBLERawRSSI = nil
            debugBLESmoothedRSSI = nil
            bleDiagnosticsStore.isPreviewRSSI = false
            debugBLELastSeenText = "--"
            bleSignalLossWorkItem?.cancel()
            bleSignalLossWorkItem = nil
            continuousWeakSince = nil
            phoneFarAwaySince = nil

            // nil RSSI：只清 live 数值。车区/鉴权中保留靠近语义，绝不因此上锁。
            let keepZone = hasCompletedBLEAuth || hasEnteredVehicleZone || bleStatus == .authenticated || state.phoneNearby
            if state.bleRssi != nil || (!keepZone && state.phoneNearby) {
                var next = state
                next.bleRssi = nil
                if !keepZone {
                    next.phoneNearby = false
                }
                apply(next)
                // 不 evaluate 上锁路径
                if !keepZone {
                    evaluateKeylessAutomation(for: next)
                }
            }
            return
        }

        let previousNearby = state.phoneNearby
        let previousHadLive = state.bleRssi != nil

        liveBLERawRSSI = rawRSSI
        liveBLELastSeenAt = Date()
        if let current = liveBLERSSI {
            let alpha = 0.35
            let smoothed = Int((Double(current) * (1 - alpha) + Double(rawRSSI) * alpha).rounded())
            liveBLERSSI = smoothed
        } else {
            liveBLERSSI = rawRSSI
        }
        let smoothedRSSI = liveBLERSSI ?? rawRSSI

        // 诊断域每秒更新：雷达 / 无感实时状态直接观察这里
        // 鉴权后的 readRSSI 会覆盖连接前用广播 RSSI 预填的 preview 值
        debugBLERawRSSI = rawRSSI
        debugBLESmoothedRSSI = smoothedRSSI
        bleDiagnosticsStore.isPreviewRSSI = false
        debugBLELastSeenText = formatTime(Date())
        scheduleBLESignalLossTimeout()

        let nextNearby = resolvedPhoneNearby(for: smoothedRSSI, previous: previousNearby)
        let proximityChanged = previousNearby != nextNearby
        let liveAvailabilityChanged = previousHadLive != true

        // 车区状态机：弱→强进入；强→弱开始离开计时（必须真实 RSSI）
        updateVehicleZoneTracking(smoothedRSSI: smoothedRSSI, nearby: nextNearby)

        if proximityChanged {
            let detail = "raw=\(rawRSSI), smoothed=\(smoothedRSSI), unlock=\(Int(keylessSettingsStore.settings.unlockThreshold)), lock=\(Int(keylessSettingsStore.settings.lockThreshold)), zone=\(hasEnteredVehicleZone ? 1 : 0)"
            debugBLELastTransitionText = "\(nextNearby ? "靠近" : "远离") · \(formatTime(Date()))"
            vehicleEventLogStore.add(.keyless, nextNearby ? "BLE判定靠近" : "BLE判定远离", detail: detail)
        }

        // Apple 风格：纯 RSSI 数字抖动不推整车 state
        // 仅在靠近语义变化 / 首次获得 live RSSI 时 apply
        if proximityChanged || liveAvailabilityChanged {
            var next = state
            next.bleRssi = smoothedRSSI
            next.phoneNearby = nextNearby
            apply(next)
            scheduleHTTPRefreshFromRealtime(reason: "ble-proximity-change")
            if !isAppInForeground {
                startHTTPPolling(immediate: false)
            }
            evaluateKeylessAutomation(for: next)
            return
        }

        // 延迟计时中需要持续评估（wait → allow），但不因数字变化重绘整页
        let settings = keylessSettingsStore.settings
        let hasActiveUnlockDelay = nextNearby
            && phoneNearbySince != nil
            && (settings.unlockEnabled || settings.powerStartEnabled)
            && settings.unlockApproachDuration > 0
        let leaveConfirm = max(settings.lockDelay, 0)
        let hasActiveLockDelay = !nextNearby
            && phoneFarAwaySince != nil
            && settings.lockEnabled
            && leaveConfirm > 0
        if hasActiveUnlockDelay || hasActiveLockDelay {
            evaluateKeylessAutomation(for: state)
        }
    }

    /// 车区追踪：
    /// - 靠近/强信号 → 进入车区（之后禁上锁，可解锁）
    /// - 连续真实弱信号 → 才开始离开确认
    /// - 信号丢失不会走到这里
    func updateVehicleZoneTracking(smoothedRSSI: Int, nearby: Bool) {
        let unlockTh = keylessSettingsStore.settings.unlockThreshold
        let lockTh = keylessSettingsStore.settings.lockThreshold
        let rssi = Double(smoothedRSSI)

        if nearby || rssi >= unlockTh {
            if externalLockRequiresExit && externalLockExitObserved {
                externalLockRequiresExit = false
                externalLockExitObserved = false
                vehicleEventLogStore.add(.keyless, "外部锁车保护解除", detail: "已确认离开后重新靠近，恢复自动解锁")
            }
            if !hasEnteredVehicleZone {
                hasEnteredVehicleZone = true
                vehicleEventLogStore.addThrottled(
                    .keyless,
                    "进入车区",
                    detail: "rssi=\(smoothedRSSI), 此后禁无感上锁、可解锁",
                    identity: "enter-vehicle-zone",
                    minimumInterval: 5
                )
            }
            continuousWeakSince = nil
            return
        }

        // 明确弱于上锁阈值：累计离开
        if rssi <= lockTh {
            if externalLockRequiresExit {
                externalLockExitObserved = true
            }
            if keylessRejectedActionUntilExit != nil {
                // 负回包后的重新尝试必须经历真实离开；信号丢失不计入。
                keylessRejectedActionUntilExit = nil
                vehicleEventLogStore.add(.keyless, "无感拒绝保护解除", detail: "已确认离开，允许下次重新靠近时再尝试")
            }
            if continuousWeakSince == nil {
                continuousWeakSince = Date()
            }
        } else {
            // 中间灰区：不算持续离开
            continuousWeakSince = nil
        }
    }

    func evaluateKeylessAutomation(for currentState: VehicleState) {
        let settings = keylessSettingsStore.settings
        guard settings.keylessEnabled else {
            resetKeylessRuntimeState()
            return
        }
        // 模式门控：插件托管 / 智能切换(旧存档) / 前台手动 至少开一个才自动
        // 前台手动：仅后台自动；插件托管：前后台都可自动
        if settings.appManual {
            guard !isAppInForeground else {
                if !didLogManualForegroundSkip {
                    vehicleEventLogStore.add(.keyless, "前台手动", detail: "App 在前台时不自动执行无感命令")
                    didLogManualForegroundSkip = true
                }
                return
            }
        } else {
            didLogManualForegroundSkip = false
        }
        guard settings.pluginTakeover || settings.smartSwitch || settings.appManual else { return }

        let leaveConfirm = max(settings.lockDelay, 0)
        let hasActiveUnlockDelay = currentState.phoneNearby
            && phoneNearbySince != nil
            && (settings.unlockEnabled || settings.powerStartEnabled)
            && settings.unlockApproachDuration > 0
        let hasActiveLockDelay = currentState.phoneFarAway
            && currentState.hasLiveBLEProximity
            && phoneFarAwaySince != nil
            && settings.lockEnabled
            && leaveConfirm > 0
        let hasActiveDelay = hasActiveUnlockDelay || hasActiveLockDelay
        let fingerprint = (currentState.locked, currentState.phoneNearby, currentState.phoneFarAway, hasEnteredVehicleZone)
        if fingerprint == (lastEvalLocked, lastEvalNearby, lastEvalFarAway, lastEvalInVehicleZone) && !hasActiveDelay {
            return
        }
        lastEvalLocked = fingerprint.0
        lastEvalNearby = fingerprint.1
        lastEvalFarAway = fingerprint.2
        lastEvalInVehicleZone = fingerprint.3

        let canUseStaleStateWithBLE = hasCompletedBLEAuth
            && (currentState.hasLiveBLEProximity || currentState.phoneFarAway)
        if !canUseStaleStateWithBLE {
            guard currentState.isFresh() else { return }
        }

        // 远离上锁必须已鉴权，且必须有 live 弱 RSSI（丢失不算）
        if currentState.phoneFarAway && !hasCompletedBLEAuth {
            return
        }

        if currentState.phoneNearby {
            if phoneNearbySince == nil {
                phoneNearbySince = Date()
            }
            hasEnteredVehicleZone = true
        } else {
            phoneNearbySince = nil
        }

        // 只有 live + 远离 才累计离开时间；信号丢失时 phoneFarAwaySince 已被清掉
        if currentState.phoneFarAway && currentState.hasLiveBLEProximity {
            if phoneFarAwaySince == nil {
                phoneFarAwaySince = continuousWeakSince ?? Date()
                if settings.lockEnabled {
                    vehicleEventLogStore.add(
                        .keyless,
                        "上锁等待",
                        detail: "确认离开中，等待 \(Int(leaveConfirm))s（按设置 lockDelay）"
                    )
                }
            }
        } else {
            phoneFarAwaySince = nil
        }

        let decisionContext = KeylessDecisionEngine.Context(
            bleAuthenticated: hasCompletedBLEAuth,
            freshnessMaxAge: 90
        )

                if settings.powerStartEnabled {
            let powerDecision = KeylessDecisionEngine.evaluatePowerStartWithDelay(
                state: currentState,
                settings: settings,
                phoneNearbySince: phoneNearbySince,
                context: KeylessDecisionEngine.Context(bleAuthenticated: hasCompletedBLEAuth)
            )
            if powerDecision != lastUnlockDecision {
                let detail = KeylessDecisionEngine.logDetail(decision: powerDecision, state: currentState, settings: settings)
                switch powerDecision {
                case .allow:
                    vehicleEventLogStore.add(.keyless, "启动电源允许", detail: detail)
                case .deny:
                    vehicleEventLogStore.add(.keyless, "启动电源拒绝", detail: detail)
                case .wait:
                    vehicleEventLogStore.add(.keyless, "启动电源等待", detail: detail)
                }
                lastUnlockDecision = powerDecision
            }
            if case .allow = powerDecision {
                executeKeylessCommandIfNeeded(action: .powerStart, state: currentState, reason: powerDecision.reason)
            }
        } else {
            let unlockDecision = KeylessDecisionEngine.evaluateUnlockWithDelay(
                state: currentState,
                settings: settings,
                phoneNearbySince: phoneNearbySince,
                context: decisionContext
            )
            if unlockDecision != lastUnlockDecision {
                let detail = KeylessDecisionEngine.logDetail(decision: unlockDecision, state: currentState, settings: settings)
                switch unlockDecision {
                case .allow:
                    vehicleEventLogStore.add(.keyless, "解锁允许", detail: detail)
                case .deny:
                    vehicleEventLogStore.add(.keyless, "解锁拒绝", detail: detail)
                case .wait:
                    vehicleEventLogStore.add(.keyless, "解锁等待", detail: detail)
                }
                lastUnlockDecision = unlockDecision
            }
            if case .allow = unlockDecision {
                executeKeylessCommandIfNeeded(action: .unlock, state: currentState, reason: unlockDecision.reason)
            }
        }

        let lockDecision = evaluateLockDecisionWithDelay(state: currentState, settings: settings, context: decisionContext)
        if lockDecision != lastLockDecision {
            let detail = KeylessDecisionEngine.logDetail(decision: lockDecision, state: currentState, settings: settings)
            switch lockDecision {
            case .allow:
                vehicleEventLogStore.add(.keyless, "上锁允许", detail: detail)
            case .deny:
                vehicleEventLogStore.add(.keyless, "上锁拒绝", detail: detail)
                postKeylessBodyOpenReminderIfNeeded(for: lockDecision, settings: settings)
            case .wait:
                vehicleEventLogStore.add(.keyless, "上锁等待", detail: detail)
            }
            lastLockDecision = lockDecision
        }
        if case .allow = lockDecision {
            executeKeylessCommandIfNeeded(action: .lock, state: currentState, reason: lockDecision.reason)
        }
    }

    func evaluateLockDecisionWithDelay(
        state: VehicleState,
        settings: KeylessSettings,
        context: KeylessDecisionEngine.Context
    ) -> KeylessDecision {
        // 硬规则：在车区可解锁、禁上锁（与物理/数字钥匙类型无关）
        if state.phoneNearby || (hasEnteredVehicleZone && !state.phoneFarAway) {
            return .deny(action: .lock, reason: "在车区禁止上锁（可解锁）")
        }
        // 从未进入车区：不做 walk-away 上锁（避免远处误锁）
        if !hasEnteredVehicleZone {
            return .deny(action: .lock, reason: "未进入过车区，不上锁")
        }
        // 信号丢失 / 无 live 弱信号：不确认离开
        if !state.hasLiveBLEProximity {
            return .deny(action: .lock, reason: "无持续弱信号，不确认离开")
        }
        if !state.phoneFarAway {
            return .deny(action: .lock, reason: "手机未确认远离")
        }

        let decision = KeylessDecisionEngine.evaluateLock(state: state, settings: settings, context: context)
        guard case .allow = decision else { return decision }

        // 离开确认：完全按设置 lockDelay；0 = 判定离开后立即上锁
        let leaveConfirm = max(settings.lockDelay, 0)
        if leaveConfirm <= 0 {
            return .allow(action: .lock, reason: decision.reason + " · 已确认离开")
        }
        guard let farSince = phoneFarAwaySince else {
            return .wait(action: .lock, reason: "确认离开中")
        }
        let elapsed = Date().timeIntervalSince(farSince)
        if elapsed < leaveConfirm {
            let remain = max(0, Int(ceil(leaveConfirm - elapsed)))
            return .wait(action: .lock, reason: "确认离开中，剩余 \(remain)s")
        }
        return .allow(action: .lock, reason: decision.reason + " · 已确认离开")
    }

    func executeKeylessCommandIfNeeded(action: KeylessAction, state: VehicleState, reason: String) {
        guard !isExecutingKeylessCommand else { return }
        let settings = keylessSettingsStore.settings
        if let lastAutoCommandAt,
           Date().timeIntervalSince(lastAutoCommandAt) < settings.cmdInterval {
            return
        }
        if action == .unlock && externalLockRequiresExit {
            vehicleEventLogStore.addThrottled(
                .keyless,
                "无感被外部锁车保护",
                detail: externalLockExitObserved ? "等待重新靠近" : "检测到外部锁车，需先离开后重新靠近",
                identity: "external-lock-protect",
                minimumInterval: 5
            )
            return
        }
        if keylessRejectedActionUntilExit == action {
            vehicleEventLogStore.addThrottled(
                .keyless,
                "无感被车辆拒绝保护",
                detail: "\(action.title)已被车辆拒绝；需先离开后重新靠近",
                identity: "keyless-rejected-protect|\(action.rawValue)",
                minimumInterval: 5
            )
            return
        }
        // 手动锁/解锁后，短时间禁止无感反向动作（日志里：刚手动锁车立刻被无感解锁）
        if let until = keylessManualSuppressUntil,
           Date() < until,
           keylessManualSuppressAction == action {
            let remain = max(0, Int(until.timeIntervalSinceNow))
            vehicleEventLogStore.addThrottled(
                .keyless,
                "无感被手动抑制",
                detail: "\(action.title) · 剩余 \(remain)s · \(reason)",
                identity: "keyless-manual-suppress|\(action.rawValue)",
                minimumInterval: 5
            )
            return
        }

        let command: VehicleCommand
        switch action {
        case .unlock:
            command = VehicleCommand(kind: .unlock, title: "无感解锁", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .bleControl)
        case .lock:
            command = VehicleCommand(kind: .lock, title: "无感上锁", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .bleControl)
        case .powerStart:
            // 不改 BLE 帧：仍走现有 powerOnReady (40E5/0312)，与快捷远程启动 BLE 路径相同
            command = VehicleCommand(kind: .remoteStart, title: "无感启动电源", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .bleControl)
        }

        let bleReady: Bool
        switch action {
        case .unlock, .lock:
            bleReady = bleManager.canSendDoorLockControl
        case .powerStart:
            bleReady = canUseBLEForVehicleControl
        }
        guard bleReady else {
            if lastBLEWaitCommandKind != command.kind {
                vehicleEventLogStore.add(.keyless, "无感等待BLE", detail: "\(command.title) | BLE 未鉴权成功")
                lastBLEWaitCommandKind = command.kind
            }
            return
        }
        lastBLEWaitCommandKind = nil
        isExecutingKeylessCommand = true
        lastAutoCommandAt = Date()
        lastAutoCommandKind = command.kind
        vehicleEventLogStore.add(.keyless, "无感命令发送", detail: "\(command.title) | \(reason)")

        let transport: VehicleCommandAsyncTransport
        switch action {
        case .unlock, .lock:
            transport = BLEDoorLockTransport(bleController: self)
        case .powerStart:
            // 与状态页 BLE 远程启动同一 transport，不改动 powerOnReady 实现
            transport = BLEVehicleControlTransport(bleController: self)
        }
        VehicleCommandExecutor.executeAsync(command, transport: transport, refresher: self) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isExecutingKeylessCommand = false
                let category: VehicleEventLogCategory
                switch result.state {
                case .failed(_), .timedOut(_):
                    category = .error
                default:
                    category = .keyless
                }
                let detail = result.userMessage.isEmpty ? result.command.title : "\(result.command.title)：\(result.userMessage)"
                if case .failed(let reason) = result.state,
                   reason.contains("车辆未接受") || result.userMessage.contains("被车辆拒绝") {
                    self.keylessRejectedActionUntilExit = action
                    self.vehicleEventLogStore.add(
                        .keyless,
                        "无感车辆拒绝保护",
                        detail: "\(action.title)被车辆拒绝；本次靠近不再重试，需先离开后重新靠近"
                    )
                }
                self.vehicleEventLogStore.add(category, "无感命令结果", detail: detail)
                if action == .lock {
                    self.confirmKeylessLockViaHTTP(after: result)
                } else {
                    self.postKeylessNotificationIfNeeded(for: action, result: result)
                }
                if case .sent = result.state {
                    self.playKeylessVibrationIfNeeded(for: action)
                }
                if case .completed = result.state {
                    self.playKeylessVibrationIfNeeded(for: action)
                }
            }
        }
    }

    /// 门尾预检拒绝属于安全提醒，独立于“上锁弹窗”开关；只在决策变化时触发，避免弱 RSSI 循环刷屏。
    func postKeylessBodyOpenReminderIfNeeded(for decision: KeylessDecision, settings: KeylessSettings) {
        guard settings.lockRequireClosedBody else { return }
        let reason = decision.reason
        guard reason == "车门未关闭" || reason == "主驾门未关闭" || reason == "后备箱未关闭" else { return }
        AppNotificationManager.shared.postKeylessNotification(title: "未执行无感上锁", body: "\(reason)，请检查车辆。")
    }

    /// HTTP 完整快照中明确未关闭的部位；未知状态不当作异常。
    func keylessOpenBodyParts(from snapshot: VehicleState) -> [String] {
        var parts: [String] = []
        if snapshot.driverDoorOpen == true {
            parts.append("主驾门未关闭")
        } else if snapshot.doorsClosed == false {
            parts.append("车门未关闭")
        }
        if snapshot.trunkOpen == true {
            parts.append("后备箱未关闭")
        }
        if snapshot.windowsClosed == false {
            parts.append("车窗未关闭")
        }
        return parts
    }

    /// 锁车 BLE 回包只说明指令被接收；最终结果必须等 HTTP 完整快照合并后确认，不能以 UI/本地回写锁态为准。
    func confirmKeylessLockViaHTTP(after result: VehicleCommandExecutionResult) {
        switch result.state {
        case .sent, .completed:
            vehicleEventLogStore.add(.keyless, "无感上锁等待 HTTP 确认", detail: "BLE 指令已发送，2 秒后请求 HTTP 完整车况")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { [weak self] in
                self?.pollHTTPOnce(userInitiated: false) { [weak self] ok, message in
                    guard let self else { return }
                    let snapshot = self.state
                    let openParts = self.keylessOpenBodyParts(from: snapshot)
                    let bodyOpen = !openParts.isEmpty
                    let bodyDetail = bodyOpen ? openParts.joined(separator: "、") : "门窗与尾门状态正常"

                    if ok, snapshot.locked == true {
                        self.vehicleEventLogStore.add(.keyless, "无感上锁 HTTP 已确认", detail: "锁=已锁 · \(bodyDetail)")
                        if self.keylessSettingsStore.settings.lockPopup {
                            AppNotificationManager.shared.postKeylessNotification(title: "无感上锁已确认", body: "HTTP 完整车况确认车辆已上锁。\(bodyOpen ? "但\(bodyDetail)，请检查车辆。" : "")")
                        }
                        if bodyOpen {
                            AppNotificationManager.shared.postKeylessNotification(title: "车辆有未关闭部位", body: "HTTP 完整车况：\(bodyDetail)。请检查车辆。")
                        }
                    } else if ok {
                        let detail = snapshot.locked == false ? "HTTP 返回车辆仍未上锁" : "HTTP 回包未提供可确认的锁态"
                        self.vehicleEventLogStore.add(.warning, "无感上锁 HTTP 未确认", detail: "\(detail) · \(bodyDetail)")
                        AppNotificationManager.shared.postKeylessNotification(title: "无感上锁未确认", body: "\(detail)。\(bodyOpen ? "\(bodyDetail)，请检查车辆。" : "")")
                    } else {
                        self.vehicleEventLogStore.add(.warning, "无感上锁 HTTP 确认失败", detail: message)
                        AppNotificationManager.shared.postKeylessNotification(title: "无感上锁待确认", body: "BLE 指令已发送，但 HTTP 完整车况刷新失败，未将本地 UI 状态作为成功依据。")
                    }
                }
            }
        case .failed(_), .timedOut(_):
            postKeylessNotificationIfNeeded(for: .lock, result: result)
        case .feedbackOnly, .planned:
            break
        }
    }

    func playKeylessVibrationIfNeeded(for action: KeylessAction) {
        let settings = keylessSettingsStore.settings
        switch action {
        case .unlock, .powerStart:
            // 启动电源复用解锁震动反馈设置
            guard settings.unlockVibrate else { return }
            playVibration(choice: keylessSettingsStore.unlockVibChoice(), intensity: settings.unlockVibStrength / 100.0)
        case .lock:
            guard settings.lockVibrate else { return }
            playVibration(choice: keylessSettingsStore.lockVibChoice(), intensity: settings.lockVibStrength / 100.0)
        }
    }

    func postKeylessNotificationIfNeeded(for action: KeylessAction, result: VehicleCommandExecutionResult) {
        let settings = keylessSettingsStore.settings
        let popupEnabled: Bool
        switch action {
        case .unlock, .powerStart:
            popupEnabled = settings.unlockPopup
        case .lock:
            popupEnabled = settings.lockPopup
        }
        guard popupEnabled else { return }

        let actionTitle = action.title
        let title: String
        switch result.state {
        case .sent, .completed:
            title = "无感\(actionTitle)已触发"
        case .failed(_), .timedOut(_):
            title = "无感\(actionTitle)失败"
        case .feedbackOnly, .planned:
            return
        }
        let body = result.userMessage.isEmpty ? result.command.detail : result.userMessage
        AppNotificationManager.shared.postKeylessNotification(title: title, body: body)
    }

    func playVibration(choice: VibrationChoice, intensity: Double) {
        switch choice {
        case .preset(let pattern):
            pattern.play(intensity: intensity)
        case .custom(let id):
            if let pattern = customVibrationStore.patterns.first(where: { $0.id == id }) {
                pattern.play(intensity: intensity)
            }
        }
    }
}
