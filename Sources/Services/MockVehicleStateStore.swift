import Foundation

// MARK: - Mock 车辆状态 store（用于 UI 联调）
final class MockVehicleStateStore: ObservableObject {
    @Published private(set) var state: VehicleState = .mockSnapshot

    func apply(_ newState: VehicleState) {
        state = newState
    }

    func simulateUnlock() {
        var next = state
        next.locked = false
        apply(next)
    }

    func simulateLock() {
        var next = state
        next.locked = true
        apply(next)
    }

    func simulateToggleAC() {
        var next = state
        next.acOn = !(state.acOn ?? false)
        apply(next)
    }

    func simulateSetACTemperature(_ temperature: Double) {
        var next = state
        next.acTemperature = temperature
        apply(next)
    }

    func simulateToggleWindows() {
        var next = state
        next.windowsClosed = !(state.windowsClosed ?? false)
        apply(next)
    }
}
