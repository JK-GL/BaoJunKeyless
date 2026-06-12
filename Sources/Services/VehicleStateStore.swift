import Foundation
import Combine

// MARK: - 车辆状态读取协议
/// StatusView 只认这个协议，不关心具体实现。
protocol VehicleStateReader: ObservableObject {
    var state: VehicleState { get }
    var dashboard: VehicleDashboardState { get }
    var cachedDashboardMetrics: VehicleDashboardMetrics { get }
}

// MARK: - 统一车辆状态 Store
/// 所有车辆状态数据的唯一来源。
/// 子类化以接入真实数据源（MQTT / BLE），StatusView 无需改动。
class VehicleStateStore: ObservableObject, VehicleStateReader {
    @Published internal(set) var state: VehicleState = .placeholder
    @Published internal(set) var dashboard: VehicleDashboardState = VehicleDashboardState()
    @Published internal(set) var cachedDashboardMetrics: VehicleDashboardMetrics = VehicleDashboardState().metrics

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
