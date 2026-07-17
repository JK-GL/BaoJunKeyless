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
}
