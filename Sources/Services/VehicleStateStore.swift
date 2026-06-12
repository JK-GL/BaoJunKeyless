import Foundation
import Combine

// MARK: - 统一车辆状态 Store
/// 所有车辆状态数据的唯一来源。
/// 子类化以接入真实数据源（MQTT / BLE），StatusView 无需改动。
class VehicleStateStore: ObservableObject {
    @Published private(set) var state: VehicleState = .placeholder
    @Published private(set) var dashboard: VehicleDashboardState = VehicleDashboardState()
    @Published private(set) var cachedDashboardMetrics: VehicleDashboardMetrics = VehicleDashboardState().metrics

    func apply(_ newState: VehicleState) {
        state = newState
    }

    func applyDashboard(_ newDashboard: VehicleDashboardState) {
        dashboard = newDashboard
        cachedDashboardMetrics = newDashboard.metrics
    }

    // MARK: - Mock 模拟接口（基类空实现，子类可覆盖）

    func simulateUnlock() {}
    func simulateLock() {}
    func simulateToggleAC() {}
    func simulateSetACTemperature(_ temperature: Double) {}
    func simulateRemoteStart() {}
    func simulateToggleWindows() {}
}
