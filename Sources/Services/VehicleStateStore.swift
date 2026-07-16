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
    @Published internal(set) var state: VehicleState
    @Published internal(set) var dashboard: VehicleDashboardState
    @Published internal(set) var cachedDashboardMetrics: VehicleDashboardMetrics
    /// 状态强制刷新版本号（合并/本地回写时递增，驱动 UI .id）
    @Published internal(set) var statusRevision: UInt64 = 0

    /// 车辆配置（登录后填充）
    @Published internal(set) var profile: VehicleProfile = VehicleProfile()

    /// 油量栏显示模式
    let fuelBarModeStore = FuelBarModeStore.shared
    var fuelBarMode: FuelBarMode {
        get { fuelBarModeStore.mode }
        set { fuelBarModeStore.mode = newValue }
    }

    private var cancellables = Set<AnyCancellable>()

    init(
        state: VehicleState = .placeholder,
        dashboard: VehicleDashboardState = VehicleDashboardState()
    ) {
        self.state = state
        self.dashboard = dashboard
        self.cachedDashboardMetrics = dashboard.metrics
        setupEnergyTypeObservers()
    }

    private func setupEnergyTypeObservers() {
        // 当 profile 或 fuelBarMode 变化时，重算能源类型
        $profile
            .combineLatest(fuelBarModeStore.$mode)
            .dropFirst() // 跳过 init 的初始值
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.recomputeEnergyType()
            }
            .store(in: &cancellables)
    }

    /// 全车状态统一入口：只有内容真变了才刷新 UI。
    /// 同值重复 MQTT/HTTP 包只更新内部时间戳，不 bump、不重算 metrics。
    @discardableResult
    func apply(_ newState: VehicleState) -> Bool {
        let incoming = newState
        // timestamp 不参与“是否变化”判断，避免仅时间刷新导致整页重绘。
        var oldNoTime = state
        var newNoTime = incoming
        oldNoTime.timestamp = .distantPast
        newNoTime.timestamp = .distantPast
        guard oldNoTime != newNoTime else {
            // 仅刷新时间戳，不触发 UI revision。
            if state.timestamp != incoming.timestamp {
                state.timestamp = incoming.timestamp
            }
            return false
        }
        state = incoming
        recomputeEnergyType()
        return true
    }

    @discardableResult
    func applyDashboard(_ newDashboard: VehicleDashboardState) -> Bool {
        let incoming = newDashboard
        // updatedAt / updatedAtText 不参与变化判断。
        var oldNoTime = dashboard
        var newNoTime = incoming
        oldNoTime.updatedAt = .distantPast
        oldNoTime.updatedAtText = ""
        newNoTime.updatedAt = .distantPast
        newNoTime.updatedAtText = ""
        guard oldNoTime != newNoTime else {
            if dashboard.updatedAt != incoming.updatedAt {
                dashboard.updatedAt = incoming.updatedAt
                dashboard.updatedAtText = incoming.updatedAtText
            }
            return false
        }
        dashboard = incoming
        cachedDashboardMetrics = incoming.metrics
        return true
    }

    func bumpStatusRevision() {
        statusRevision &+= 1
    }

    /// 状态或仪表任一变化才推进 UI revision。
    @discardableResult
    func applyVehicleSnapshot(
        state newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        bumpIfChanged: Bool = true
    ) -> Bool {
        let stateChanged = apply(newState)
        let dashChanged = applyDashboard(newDashboard)
        let changed = stateChanged || dashChanged
        if changed, bumpIfChanged {
            bumpStatusRevision()
        }
        return changed
    }

    func applyProfile(_ newProfile: VehicleProfile) {
        profile = newProfile
        recomputeEnergyType()
    }

    func setFuelBarMode(_ mode: FuelBarMode) {
        fuelBarModeStore.setMode(mode)
        recomputeEnergyType()
    }

    /// 根据 profile + 状态 + 模式，重算能源类型
    private func recomputeEnergyType() {
        let detected = profile.detectEnergyType(fuelBarMode: fuelBarMode, status: state)
        let newType: VehicleEnergyType = (detected == .pureElectric) ? .pureElectric : .plugInHybrid
        if dashboard.energyType != newType {
            dashboard.energyType = newType
            cachedDashboardMetrics = dashboard.metrics
        }
    }
}
