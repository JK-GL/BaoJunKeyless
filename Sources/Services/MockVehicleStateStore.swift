import Foundation

// MARK: - Mock 车辆状态 store（用于 UI 联调）
/// 继承自 VehicleStateStore，添加 mock 模拟方法。
/// 未来接入真实数据源时，只需替换为 MQTTVehicleStateStore 等子类。
final class MockVehicleStateStore: VehicleStateStore {

    init(initialDashboard: VehicleDashboardState = VehicleDashboardState()) {
        super.init(state: .mockSnapshot, dashboard: initialDashboard)
    }

    override func simulateUnlock() {
        var next = state
        next.locked = false
        apply(next)

        var dash = dashboard
        dash.lockStatusText = "未锁"
        applyDashboard(dash)
    }

    override func simulateLock() {
        var next = state
        next.locked = true
        apply(next)

        var dash = dashboard
        dash.lockStatusText = "已锁车"
        applyDashboard(dash)
    }

    override func simulateToggleAC() {
        var next = state
        next.acOn = !(state.acOn ?? false)
        apply(next)

        var dash = dashboard
        dash.acTemperatureText = "\(Int(next.acTemperature ?? 22))°C"
        applyDashboard(dash)
    }

    override func simulateSetACTemperature(_ temperature: Double) {
        var next = state
        next.acTemperature = temperature
        apply(next)

        var dash = dashboard
        dash.acTemperatureText = "\(Int(temperature))°C"
        applyDashboard(dash)
    }

    override func simulateRemoteStart() {
        var next = state
        next.power = next.power == .off ? .ready : .off
        apply(next)

        var dash = dashboard
        dash.updatedAtText = "刚刚"
        applyDashboard(dash)
    }

    override func simulateToggleWindows() {
        var next = state
        next.windowsClosed = !(state.windowsClosed ?? false)
        apply(next)

        var dash = dashboard
        dash.windowStatusText = next.windowsClosed == true ? "全关" : "未关"
        applyDashboard(dash)
    }
}
