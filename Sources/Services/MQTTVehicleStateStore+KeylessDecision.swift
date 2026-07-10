import Foundation

extension MQTTVehicleStateStore {
    func resetKeylessRuntimeState() {
        lastUnlockDecision = nil
        lastLockDecision = nil
        lastEvalLocked = nil
        lastEvalNearby = nil
        lastEvalFarAway = nil
        phoneNearbySince = nil
        phoneFarAwaySince = nil
        bleScanStartedAt = nil
        hasCompletedBLEAuth = false
        userManuallyStoppedBLE = false
        didLogManualForegroundSkip = false
        lastBLEWaitCommandKind = nil
        resetBLEDiagnosticCycle()
        resetNearbyBLEDevices()
        bleSignalLossWorkItem?.cancel()
        bleSignalLossWorkItem = nil
        isExecutingKeylessCommand = false
    }

    func applyLiveBLEOverlay(to baseState: VehicleState) -> VehicleState {
        guard let rssi = liveBLERSSI else {
            var next = baseState
            if next.bleRssi != nil || next.phoneNearby {
                next.bleRssi = nil
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
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.liveBLERawRSSI = nil
            self.liveBLERSSI = nil
            self.liveBLELastSeenAt = nil
            self.debugBLERawRSSI = nil
            self.debugBLESmoothedRSSI = nil
            self.debugBLELastSeenText = "--"
            self.debugBLELastTransitionText = "BLE信号丢失 · \(formatTime(Date()))"
            self.logVehicleEvent(.warning, "BLE信号丢失", detail: "连续 3s 未收到 RSSI，按远离处理", identity: "signal-loss", minimumInterval: 8)
            var next = self.state
            next.bleRssi = nil
            next.phoneNearby = false
            self.apply(next)
            self.evaluateKeylessAutomation(for: next)
        }
        bleSignalLossWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    func applyLiveBLERSSI(_ rawRSSI: Int?) {
        guard let rawRSSI else {
            liveBLERawRSSI = nil
            liveBLERSSI = nil
            liveBLELastSeenAt = nil
            debugBLERawRSSI = nil
            debugBLESmoothedRSSI = nil
            debugBLELastSeenText = "--"
            bleSignalLossWorkItem?.cancel()
            bleSignalLossWorkItem = nil

            // 只有靠近语义或 live 可用性变化时才推整车 state
            if state.phoneNearby || state.bleRssi != nil {
                var next = state
                next.bleRssi = nil
                next.phoneNearby = false
                apply(next)
                evaluateKeylessAutomation(for: next)
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
        debugBLERawRSSI = rawRSSI
        debugBLESmoothedRSSI = smoothedRSSI
        debugBLELastSeenText = formatTime(Date())
        scheduleBLESignalLossTimeout()

        let nextNearby = resolvedPhoneNearby(for: smoothedRSSI, previous: previousNearby)
        let proximityChanged = previousNearby != nextNearby
        let liveAvailabilityChanged = previousHadLive != true

        if proximityChanged {
            let detail = "raw=\(rawRSSI), smoothed=\(smoothedRSSI), unlock=\(Int(keylessSettingsStore.settings.unlockThreshold)), lock=\(Int(keylessSettingsStore.settings.lockThreshold))"
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
            evaluateKeylessAutomation(for: next)
            return
        }

        // 延迟计时中需要持续评估（wait → allow），但不因数字变化重绘整页
        let settings = keylessSettingsStore.settings
        let hasActiveUnlockDelay = nextNearby
            && phoneNearbySince != nil
            && settings.unlockEnabled
            && settings.unlockApproachDuration > 0
        let hasActiveLockDelay = !nextNearby
            && phoneFarAwaySince != nil
            && settings.lockEnabled
            && settings.lockDelay > 0
        if hasActiveUnlockDelay || hasActiveLockDelay {
            evaluateKeylessAutomation(for: state)
        }
    }

    func evaluateKeylessAutomation(for currentState: VehicleState) {
        let settings = keylessSettingsStore.settings
        guard settings.keylessEnabled else {
            resetKeylessRuntimeState()
            return
        }
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

        let hasActiveUnlockDelay = currentState.phoneNearby
            && phoneNearbySince != nil
            && settings.unlockEnabled
            && settings.unlockApproachDuration > 0
        let hasActiveLockDelay = currentState.phoneFarAway
            && phoneFarAwaySince != nil
            && settings.lockEnabled
            && settings.lockDelay > 0
        let hasActiveDelay = hasActiveUnlockDelay || hasActiveLockDelay
        let fingerprint = (currentState.locked, currentState.phoneNearby, currentState.phoneFarAway)
        if fingerprint == (lastEvalLocked, lastEvalNearby, lastEvalFarAway) && !hasActiveDelay {
            return
        }
        lastEvalLocked = fingerprint.0
        lastEvalNearby = fingerprint.1
        lastEvalFarAway = fingerprint.2

        let canUseStaleStateWithBLE = hasCompletedBLEAuth
            && (currentState.hasLiveBLEProximity || currentState.phoneFarAway)
        if !canUseStaleStateWithBLE {
            guard currentState.isFresh() else { return }
        }

        if currentState.phoneFarAway && !hasCompletedBLEAuth {
            return
        }

        if currentState.phoneNearby {
            if phoneNearbySince == nil {
                phoneNearbySince = Date()
            }
        } else {
            phoneNearbySince = nil
        }

        if currentState.phoneFarAway {
            if phoneFarAwaySince == nil {
                phoneFarAwaySince = Date()
                if settings.lockEnabled {
                    vehicleEventLogStore.add(.keyless, "上锁等待", detail: "手机远离，等待 \(Int(settings.lockDelay))s")
                }
            }
        } else {
            phoneFarAwaySince = nil
        }

        let decisionContext = KeylessDecisionEngine.Context(
            bleAuthenticated: hasCompletedBLEAuth,
            freshnessMaxAge: 90
        )

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

        let lockDecision = evaluateLockDecisionWithDelay(state: currentState, settings: settings, context: decisionContext)
        if lockDecision != lastLockDecision {
            let detail = KeylessDecisionEngine.logDetail(decision: lockDecision, state: currentState, settings: settings)
            switch lockDecision {
            case .allow:
                vehicleEventLogStore.add(.keyless, "上锁允许", detail: detail)
            case .deny:
                vehicleEventLogStore.add(.keyless, "上锁拒绝", detail: detail)
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
        let decision = KeylessDecisionEngine.evaluateLock(state: state, settings: settings, context: context)
        guard case .allow = decision else { return decision }
        let delay = max(settings.lockDelay, 0)
        guard delay > 0 else { return decision }
        guard let farSince = phoneFarAwaySince else {
            return .wait(action: .lock, reason: "手机远离，等待上锁延迟")
        }
        let elapsed = Date().timeIntervalSince(farSince)
        guard elapsed >= delay else {
            return .wait(action: .lock, reason: "手机远离，等待上锁延迟")
        }
        return decision
    }

    func executeKeylessCommandIfNeeded(action: KeylessAction, state: VehicleState, reason: String) {
        guard !isExecutingKeylessCommand else { return }
        let settings = keylessSettingsStore.settings
        if let lastAutoCommandAt,
           Date().timeIntervalSince(lastAutoCommandAt) < settings.cmdInterval {
            return
        }

        let command: VehicleCommand
        switch action {
        case .unlock:
            command = VehicleCommand(kind: .unlock, title: "无感解锁", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .bleControl)
        case .lock:
            command = VehicleCommand(kind: .lock, title: "无感上锁", detail: reason, requestedTemperature: nil, source: .keyless, transportHint: .bleControl)
        }

        guard bleManager.canSendDoorLockControl else {
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

        let transport = BLEDoorLockTransport(bleController: self)
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
                self.vehicleEventLogStore.add(category, "无感命令结果", detail: detail)
                self.postKeylessNotificationIfNeeded(for: action, result: result)
                if case .sent = result.state {
                    self.playKeylessVibrationIfNeeded(for: action)
                }
                if case .completed = result.state {
                    self.playKeylessVibrationIfNeeded(for: action)
                }
            }
        }
    }

    func playKeylessVibrationIfNeeded(for action: KeylessAction) {
        let settings = keylessSettingsStore.settings
        switch action {
        case .unlock:
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
        case .unlock:
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
