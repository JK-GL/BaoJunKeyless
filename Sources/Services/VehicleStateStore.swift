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
/// 热路径字段不用 @Published 自动广播，改为“内容真变才 objectWillChange”，
/// 同一快照内 state+dashboard 合并为一次 UI 刷新，避免点击/弹窗发黏。
class VehicleStateStore: ObservableObject, VehicleStateReader {
    private var _state: VehicleState
    private var _dashboard: VehicleDashboardState
    private var _cachedDashboardMetrics: VehicleDashboardMetrics
    private var _profile: VehicleProfile = VehicleProfile()

    var state: VehicleState { _state }
    var dashboard: VehicleDashboardState { _dashboard }
    var cachedDashboardMetrics: VehicleDashboardMetrics { _cachedDashboardMetrics }
    var profile: VehicleProfile { _profile }

    /// 仅调试/兼容保留；不驱动 UI。
    internal(set) var statusRevision: UInt64 = 0

    /// 油量栏显示模式
    let fuelBarModeStore = FuelBarModeStore.shared
    var fuelBarMode: FuelBarMode {
        get { fuelBarModeStore.mode }
        set { fuelBarModeStore.mode = newValue }
    }

    /// 批量写入期间合并为一次 objectWillChange。
    private var isBatchingPublishes = false
    private var pendingPublish = false
    private var cancellables = Set<AnyCancellable>()

    init(
        state: VehicleState = .placeholder,
        dashboard: VehicleDashboardState = VehicleDashboardState()
    ) {
        self._state = state
        self._dashboard = dashboard
        self._cachedDashboardMetrics = dashboard.metrics
        setupEnergyTypeObservers()
    }

    private func setupEnergyTypeObservers() {
        fuelBarModeStore.$mode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeEnergyType()
            }
            .store(in: &cancellables)
    }

    private func beginPublishBatch() {
        isBatchingPublishes = true
        pendingPublish = false
    }

    private func endPublishBatch() {
        isBatchingPublishes = false
        if pendingPublish {
            pendingPublish = false
            objectWillChange.send()
        }
    }

    private func publishIfNeeded() {
        if isBatchingPublishes {
            pendingPublish = true
        } else {
            objectWillChange.send()
        }
    }

    /// 全车状态统一入口：只有内容真变了才刷新 UI。
    @discardableResult
    func apply(_ newState: VehicleState) -> Bool {
        let incoming = newState
        var oldNoTime = _state
        var newNoTime = incoming
        oldNoTime.timestamp = .distantPast
        newNoTime.timestamp = .distantPast
        guard oldNoTime != newNoTime else {
            if _state.timestamp != incoming.timestamp {
                _state.timestamp = incoming.timestamp
            }
            return false
        }

        let energyRelevantChanged =
            oldNoTime.fuelLevel != newNoTime.fuelLevel
            || oldNoTime.fuelRange != newNoTime.fuelRange
            || oldNoTime.oilRange != newNoTime.oilRange

        publishIfNeeded()
        _state = incoming
        if energyRelevantChanged {
            recomputeEnergyType(publish: false)
        }
        return true
    }

    @discardableResult
    func applyDashboard(_ newDashboard: VehicleDashboardState) -> Bool {
        let incoming = newDashboard
        var oldNoTime = _dashboard
        var newNoTime = incoming
        oldNoTime.updatedAt = .distantPast
        oldNoTime.updatedAtText = ""
        newNoTime.updatedAt = .distantPast
        newNoTime.updatedAtText = ""
        guard oldNoTime != newNoTime else {
            if _dashboard.updatedAt != incoming.updatedAt {
                _dashboard.updatedAt = incoming.updatedAt
                _dashboard.updatedAtText = incoming.updatedAtText
            }
            return false
        }

        let nextMetrics = incoming.metrics
        let metricsChanged = _cachedDashboardMetrics != nextMetrics

        publishIfNeeded()
        _dashboard = incoming
        if metricsChanged {
            _cachedDashboardMetrics = nextMetrics
        }
        return true
    }

    func bumpStatusRevision() {
        statusRevision &+= 1
    }

    /// 状态或仪表任一变化时，合并为一次 UI 刷新。
    @discardableResult
    func applyVehicleSnapshot(
        state newState: VehicleState,
        dashboard newDashboard: VehicleDashboardState,
        bumpIfChanged: Bool = true
    ) -> Bool {
        beginPublishBatch()
        let stateChanged = apply(newState)
        let dashChanged = applyDashboard(newDashboard)
        let changed = stateChanged || dashChanged
        if changed, bumpIfChanged {
            bumpStatusRevision()
        }
        endPublishBatch()
        return changed
    }

    func applyProfile(_ newProfile: VehicleProfile) {
        guard _profile != newProfile else { return }
        publishIfNeeded()
        _profile = newProfile
        recomputeEnergyType(publish: false)
    }

    func setFuelBarMode(_ mode: FuelBarMode) {
        fuelBarModeStore.setMode(mode)
        recomputeEnergyType()
    }

    private func recomputeEnergyType(publish: Bool = true) {
        let detected = profile.detectEnergyType(fuelBarMode: fuelBarMode, status: state)
        let newType: VehicleEnergyType = (detected == .pureElectric) ? .pureElectric : .plugInHybrid
        guard _dashboard.energyType != newType else { return }
        if publish {
            publishIfNeeded()
        }
        _dashboard.energyType = newType
        let nextMetrics = _dashboard.metrics
        if _cachedDashboardMetrics != nextMetrics {
            _cachedDashboardMetrics = nextMetrics
        }
    }
}
