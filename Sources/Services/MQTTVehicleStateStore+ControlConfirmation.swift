import Foundation

// MARK: - 官方车控确认链
// HTTP 受理 → 等待 MQTT app/status 或 HTTP 全量的期望字段。
// /vehicle/control 的 SgmwAppControlResult 仅为附加诊断，不能作为必经确认。

extension MQTTVehicleStateStore {
    func beginControlStateConfirmation(_ command: VehicleCommand) {
        guard controlExpectedDescription(for: command) != nil else { return }

        pendingControlStateTimeoutWorkItem?.cancel()
        let now = Date()
        let pending = PendingVehicleControlStateConfirmation(
            id: UUID(),
            command: command,
            startedAt: now,
            deadline: now.addingTimeInterval(Self.controlStateConfirmationTimeout)
        )
        pendingControlStateConfirmation = pending
        latestControlStateConfirmation = nil

        vehicleEventLogStore.add(
            .action,
            "控制确认开始",
            detail: "command=\(command.title) · expected=\(controlExpectedDescription(for: command) ?? "--") · MQTT status/HTTP 任一命中 · timeout=\(Int(Self.controlStateConfirmationTimeout))s"
        )

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let current = self.pendingControlStateConfirmation,
                  current.id == pending.id else { return }
            self.pendingControlStateConfirmation = nil
            self.pendingControlStateTimeoutWorkItem = nil
            let confirmation = VehicleControlStateConfirmation(
                commandTitle: current.command.title,
                expectedDescription: self.controlExpectedDescription(for: current.command) ?? "--",
                observedDescription: "未在 MQTT status 或 HTTP 车况中看到目标状态",
                source: .timeout,
                elapsedMillis: Int(Date().timeIntervalSince(current.startedAt) * 1000)
            )
            self.latestControlStateConfirmation = confirmation
            self.vehicleEventLogStore.add(
                .warning,
                "控制状态未确认",
                detail: "command=\(confirmation.commandTitle) · expected=\(confirmation.expectedDescription) · waited=\(confirmation.elapsedMillis)ms · HTTP 已受理，但 MQTT status/HTTP 均未命中"
            )
        }
        pendingControlStateTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.controlStateConfirmationTimeout, execute: work)
    }

    func cancelControlStateConfirmation(_ command: VehicleCommand) {
        guard let pending = pendingControlStateConfirmation, pending.command == command else { return }
        pendingControlStateTimeoutWorkItem?.cancel()
        pendingControlStateTimeoutWorkItem = nil
        pendingControlStateConfirmation = nil
    }

    /// 在真实 MQTT status 或 HTTP 原始车况落地后调用。
    /// 空/缺字段不会匹配；本地即时 UI 状态不会参与匹配。
    func confirmPendingControlStateIfMatched(
        fields: [String: String],
        source: VehicleControlStateConfirmationSource,
        observedAt: Date
    ) {
        guard let pending = pendingControlStateConfirmation else { return }
        // 车端 collectTime 允许比本机发令早最多 2 秒：HTTP 成功回调可能晚于 status MQTT。
        guard observedAt >= pending.startedAt.addingTimeInterval(-2) else { return }
        guard let observed = controlObservedDescriptionIfMatched(for: pending.command, fields: fields) else { return }

        pendingControlStateTimeoutWorkItem?.cancel()
        pendingControlStateTimeoutWorkItem = nil
        pendingControlStateConfirmation = nil

        let confirmation = VehicleControlStateConfirmation(
            commandTitle: pending.command.title,
            expectedDescription: controlExpectedDescription(for: pending.command) ?? "--",
            observedDescription: observed,
            source: source,
            elapsedMillis: max(0, Int(Date().timeIntervalSince(pending.startedAt) * 1000))
        )
        latestControlStateConfirmation = confirmation
        vehicleEventLogStore.add(
            .action,
            "控制状态已确认",
            detail: "command=\(confirmation.commandTitle) · source=\(source.title) · expected=\(confirmation.expectedDescription) · observed=\(confirmation.observedDescription) · elapsed=\(confirmation.elapsedMillis)ms"
        )
    }

    private func controlExpectedDescription(for command: VehicleCommand) -> String? {
        switch command.kind {
        case .lock: return "doorLockStatus=0（已锁）"
        case .unlock: return "doorLockStatus=1（未锁）"
        case .openWindows: return "车窗=未关"
        case .closeWindows: return "车窗=全关"
        case .acOn, .quickCool: return "acStatus=开"
        case .acOff: return "acStatus=关"
        case .setTemperature:
            guard let temp = command.requestedTemperature else { return nil }
            return "accCntTemp=\(Int(temp.rounded()))°C"
        case .remoteStart, .remoteStop, .findCar:
            // 本车 engineStatus 常空，寻车也没有稳定状态字段；只保留 HTTP 受理与后续状态观察。
            return nil
        }
    }

    private func controlObservedDescriptionIfMatched(
        for command: VehicleCommand,
        fields: [String: String]
    ) -> String? {
        switch command.kind {
        case .lock:
            guard fields["doorLockStatus"] != nil, parseLocked(fields["doorLockStatus"]) == true else { return nil }
            return "doorLockStatus=0（已锁）"
        case .unlock:
            guard fields["doorLockStatus"] != nil, parseLocked(fields["doorLockStatus"]) == false else { return nil }
            return "doorLockStatus=1（未锁）"
        case .openWindows:
            guard hasAnyWindowStatusField(fields), parseWindowsClosed(fields) == false else { return nil }
            return "车窗=未关"
        case .closeWindows:
            guard hasAnyWindowStatusField(fields), parseWindowsClosed(fields) == true else { return nil }
            return "车窗=全关"
        case .acOn, .quickCool:
            guard fields["acStatus"] != nil, parseACStatus(fields["acStatus"]) == true else { return nil }
            let temp = fields["accCntTemp"].map { " · accCntTemp=\($0)°C" } ?? ""
            return "acStatus=开\(temp)"
        case .acOff:
            guard fields["acStatus"] != nil, parseACStatus(fields["acStatus"]) == false else { return nil }
            return "acStatus=关"
        case .setTemperature:
            guard let expected = command.requestedTemperature,
                  let observed = parseDouble(fields["accCntTemp"]),
                  abs(observed - expected) < 0.51 else { return nil }
            return "accCntTemp=\(Int(observed.rounded()))°C"
        case .remoteStart, .remoteStop, .findCar:
            return nil
        }
    }

    private func hasAnyWindowStatusField(_ fields: [String: String]) -> Bool {
        [
            "windowStatus", "window1Status", "window2Status", "window3Status", "window4Status",
            "window1OpenDegree", "window2OpenDegree", "window3OpenDegree", "window4OpenDegree",
            "windowHalfOpenStatus", "window1HalfOpenStatus", "window2HalfOpenStatus",
            "window3HalfOpenStatus", "window4HalfOpenStatus"
        ].contains { fields[$0] != nil }
    }
}
