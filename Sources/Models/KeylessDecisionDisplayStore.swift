import Foundation
import Combine

/// 无感实时卡专用的最小展示快照。
/// 车辆状态主 Store 可以高频更新电量、位置、温度等；这些字段不应让无感卡重绘。
struct KeylessDecisionDisplaySnapshot: Equatable {
    var timestamp: Date
    var online: Bool
    var locked: Bool?
    var doorsClosed: Bool?
    var driverDoorOpen: Bool?
    var trunkOpen: Bool?
    var windowsClosed: Bool?
    var acOn: Bool?
    var acTemperature: Double?
    var gear: VehicleGear
    var power: VehiclePowerState
    var speed: Double?
    var physicalKeyPosition: PhysicalKeyPosition
    var bleRssi: Int?
    var phoneNearby: Bool
    var phoneNearbySince: Date?
    var phoneFarAwaySince: Date?
    var hasCompletedBLEAuth: Bool

    static let placeholder = KeylessDecisionDisplaySnapshot(
        timestamp: .distantPast,
        online: false,
        locked: nil,
        doorsClosed: nil,
        driverDoorOpen: nil,
        trunkOpen: nil,
        windowsClosed: nil,
        acOn: nil,
        acTemperature: nil,
        gear: .unknown,
        power: .unknown,
        speed: nil,
        physicalKeyPosition: .unknown,
        bleRssi: nil,
        phoneNearby: false,
        phoneNearbySince: nil,
        phoneFarAwaySince: nil,
        hasCompletedBLEAuth: false
    )

    init(
        state: VehicleState,
        hasCompletedBLEAuth: Bool,
        phoneNearbySince: Date?,
        phoneFarAwaySince: Date?
    ) {
        timestamp = state.timestamp
        online = state.online
        locked = state.locked
        doorsClosed = state.doorsClosed
        driverDoorOpen = state.driverDoorOpen
        trunkOpen = state.trunkOpen
        windowsClosed = state.windowsClosed
        acOn = state.acOn
        acTemperature = state.acTemperature
        gear = state.gear
        power = state.power
        speed = state.speed
        physicalKeyPosition = state.physicalKeyPosition
        bleRssi = state.bleRssi
        phoneNearby = state.phoneNearby
        self.phoneNearbySince = phoneNearbySince
        self.phoneFarAwaySince = phoneFarAwaySince
        self.hasCompletedBLEAuth = hasCompletedBLEAuth
    }

    var asVehicleState: VehicleState {
        VehicleState(
            timestamp: timestamp,
            online: online,
            locked: locked,
            doorsClosed: doorsClosed,
            driverDoorOpen: driverDoorOpen,
            trunkOpen: trunkOpen,
            windowsClosed: windowsClosed,
            acOn: acOn,
            acTemperature: acTemperature,
            gear: gear,
            power: power,
            speed: speed,
            physicalKeyPosition: physicalKeyPosition,
            bleRssi: bleRssi,
            phoneNearby: phoneNearby
        )
    }
}

/// 独立于主仪表盘的无感展示域；只在判定输入变化时发布。
final class KeylessDecisionDisplayStore: ObservableObject {
    static let shared = KeylessDecisionDisplayStore()

    @Published private(set) var snapshot = KeylessDecisionDisplaySnapshot.placeholder

    func ingest(
        state: VehicleState,
        hasCompletedBLEAuth: Bool,
        phoneNearbySince: Date?,
        phoneFarAwaySince: Date?
    ) {
        let next = KeylessDecisionDisplaySnapshot(
            state: state,
            hasCompletedBLEAuth: hasCompletedBLEAuth,
            phoneNearbySince: phoneNearbySince,
            phoneFarAwaySince: phoneFarAwaySince
        )
        guard next != snapshot else { return }
        snapshot = next
    }
}
