import Foundation

// MARK: - Mock 车辆状态 store（用于 UI 联调）
final class MockVehicleStateStore: ObservableObject {
    @Published private(set) var state: VehicleState = .mockSnapshot
    @Published private(set) var dashboard: VehicleDashboardState = VehicleDashboardState()
    @Published private(set) var cachedDashboardMetrics: VehicleDashboardMetrics = VehicleDashboardState().metrics

    func apply(_ newState: VehicleState) {
        state = newState
    }

    func applyDashboard(_ newDashboard: VehicleDashboardState) {
        dashboard = newDashboard
        cachedDashboardMetrics = newDashboard.metrics
    }

    func simulateUnlock() {
        var next = state
        next.locked = false
        apply(next)

        var dash = dashboard
        dash.lockStatusText = "未锁"
        applyDashboard(dash)
    }

    func simulateLock() {
        var next = state
        next.locked = true
        apply(next)

        var dash = dashboard
        dash.lockStatusText = "已锁车"
        applyDashboard(dash)
    }

    func simulateToggleAC() {
        var next = state
        next.acOn = !(state.acOn ?? false)
        apply(next)

        var dash = dashboard
        dash.acTemperatureText = "\(Int(next.acTemperature ?? 22))°C"
        applyDashboard(dash)
    }

    func simulateSetACTemperature(_ temperature: Double) {
        var next = state
        next.acTemperature = temperature
        apply(next)

        var dash = dashboard
        dash.acTemperatureText = "\(Int(temperature))°C"
        applyDashboard(dash)
    }

    func simulateRemoteStart() {
        var next = state
        next.power = next.power == .off ? .ready : .off
        apply(next)

        var dash = dashboard
        dash.updatedAtText = "刚刚"
        applyDashboard(dash)
    }

    func simulateToggleWindows() {
        var next = state
        next.windowsClosed = !(state.windowsClosed ?? false)
        apply(next)

        var dash = dashboard
        dash.windowStatusText = next.windowsClosed == true ? "全关" : "未关"
        applyDashboard(dash)
    }
}
