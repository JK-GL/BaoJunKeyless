import Foundation

// MARK: - 多水管进水契约（R1 阶段1）
//
// 只做命名与唯一入口，不改变合并算法、轮询秒数、无感规则、UI。
//
// Pipe HTTP  → ingestHTTPAuthority          → mergeHTTPBaseState → applyVehicleSnapshot
// Pipe MQTT  → ingestMQTTStatusPayload      → 电源/空调即时 + 其余叫醒 HTTP
// Pipe BLE   → ingestBLEDoorLockLocal 等    → 本地短回写 + 可叫醒 HTTP
//
// 禁止：旁路直接改 state/dashboard 绕过上述入口（阶段2收口检查）。
// 详见 docs/R1_D1_architecture_freeze.md

extension MQTTVehicleStateStore {

    /// 水管1：HTTP 完整权威快照进总表。
    /// - 语义同 `mergeHTTPBaseState`（旧 collectTime 丢弃、锁保护窗、门窗权威等均不变）。
    @discardableResult
    func ingestHTTPAuthority(
        newState: VehicleState,
        dashboard: VehicleDashboardState,
        mode: VehicleHTTPMergeMode = .full,
        httpCollectAt: Date? = nil,
        sourceFields: [String: String] = [:]
    ) -> String {
        mergeHTTPBaseState(
            newState: newState,
            dashboard: dashboard,
            mode: mode,
            httpCollectAt: httpCollectAt,
            sourceFields: sourceFields
        )
    }

    /// 水管2：MQTT `/vehicle/app/status` 原始 payload。
    /// - 语义同 `handleVehicleStatus`（半包不盖门窗；电源/空调可即时；其余 schedule HTTP）。
    func ingestMQTTStatusPayload(_ data: Data) {
        handleVehicleStatus(data)
    }

    /// 水管3：BLE 门锁成功后的本地短回写（约 15s 保护 + 唤醒 HTTP）。
    /// - 语义同 `applyLocalDoorLockState`。
    func ingestBLEDoorLockLocal(
        locked: Bool,
        source: String,
        suppressOppositeKeyless: Bool = false
    ) {
        applyLocalDoorLockState(
            locked: locked,
            source: source,
            suppressOppositeKeyless: suppressOppositeKeyless
        )
    }

    /// 水管3：明确电源状态本地确认（BLE 回包 / MQTT 电源字段等）。
    /// - 语义同 `applyExplicitPowerState`。
    func ingestExplicitPowerLocal(_ power: VehiclePowerState, source: String) {
        applyExplicitPowerState(power, source: source)
    }

    /// 水管3：车窗总览本地短回写（HTTP 开/关窗受理成功后用）。
    /// 只改总览 windowsClosed + 文案；明细仍等 HTTP 权威收敛。
    func ingestHTTPWindowsOverviewLocal(closed: Bool, source: String) {
        var next = state
        let previous = next.windowsClosed
        let now = Date()
        next.windowsClosed = closed
        next.timestamp = now
        next.online = true

        var dash = dashboard
        dash.windowStatusText = closed ? "全关" : "未关"
        dash.updatedAt = now
        dash.updatedAtText = formatTime(now)

        guard applyVehicleSnapshot(state: next, dashboard: dash, bumpIfChanged: true) || previous != closed else {
            return
        }
        vehicleEventLogStore.add(
            .action,
            "本地车窗总览已更新",
            detail: "\(source) · \(previous.map { $0 ? "全关" : "未关" } ?? "未知") → \(closed ? "全关" : "未关")"
        )
        scheduleHTTPRefreshFromRealtime(reason: "http-windows-accepted")
    }

    /// HTTP 车控接口「已受理」成功后的即时回写（不替代最终 HTTP 权威）。
    /// 由 `HTTPControlTransport` 在 send 成功时调用。
    func applyAcceptedHTTPControlIfPossible(_ command: VehicleCommand) {
        switch command.kind {
        case .lock:
            ingestBLEDoorLockLocal(
                locked: true,
                source: "HTTP锁车已受理",
                suppressOppositeKeyless: command.source != .keyless
            )
        case .unlock:
            ingestBLEDoorLockLocal(
                locked: false,
                source: "HTTP解锁已受理",
                suppressOppositeKeyless: command.source != .keyless
            )
        case .remoteStart:
            ingestExplicitPowerLocal(.on, source: "HTTP上电已受理")
        case .remoteStop:
            ingestExplicitPowerLocal(.off, source: "HTTP熄火已受理")
        case .acOn, .quickCool:
            _ = applyAuthoritativeClimateState(
                acOn: true,
                temperature: command.requestedTemperature,
                source: "HTTP空调已受理",
                observedAt: Date(),
                scheduleHTTPConfirm: false
            )
        case .acOff:
            _ = applyAuthoritativeClimateState(
                acOn: false,
                temperature: nil,
                source: "HTTP关空调已受理",
                observedAt: Date(),
                scheduleHTTPConfirm: false
            )
        case .setTemperature:
            _ = applyAuthoritativeClimateState(
                acOn: nil,
                temperature: command.requestedTemperature,
                source: "HTTP设温已受理",
                observedAt: Date(),
                scheduleHTTPConfirm: false
            )
        case .openWindows:
            ingestHTTPWindowsOverviewLocal(closed: false, source: "HTTP开窗已受理")
        case .closeWindows:
            ingestHTTPWindowsOverviewLocal(closed: true, source: "HTTP关窗已受理")
        case .findCar:
            break
        }
    }
}
