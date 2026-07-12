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

    func apply(_ newState: VehicleState) {
        state = newState
        recomputeEnergyType()
    }

    func applyDashboard(_ newDashboard: VehicleDashboardState) {
        dashboard = newDashboard
        cachedDashboardMetrics = newDashboard.metrics
    }

    func bumpStatusRevision() {
        statusRevision &+= 1
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
