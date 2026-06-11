import Foundation

// MARK: - 车辆档位
enum VehicleGear: String, Codable, CaseIterable {
    case p = "P"
    case r = "R"
    case n = "N"
    case d = "D"
    case unknown

    var title: String {
        switch self {
        case .p: return "P"
        case .r: return "R"
        case .n: return "N"
        case .d: return "D"
        case .unknown: return "—"
        }
    }
}

// MARK: - 车辆电源状态
enum VehiclePowerState: String, Codable, CaseIterable {
    case off
    case acc
    case on
    case ready
    case unknown

    var title: String {
        switch self {
        case .off:    return "熄火"
        case .acc:    return "ACC"
        case .on:     return "通电"
        case .ready:  return "就绪"
        case .unknown: return "—"
        }
    }
}

// MARK: - 车辆状态快照
struct VehicleState: Equatable {
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
    var physicalKeyInside: Bool?
    var bleRssi: Int?
    var phoneNearby: Bool

    static var placeholder: VehicleState {
        VehicleState(
            timestamp: Date(),
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
            physicalKeyInside: nil,
            bleRssi: nil,
            phoneNearby: false
        )
    }

    static var mockSnapshot: VehicleState {
        VehicleState(
            timestamp: Date(),
            online: true,
            locked: true,
            doorsClosed: true,
            driverDoorOpen: false,
            trunkOpen: false,
            windowsClosed: false,
            acOn: false,
            acTemperature: 22,
            gear: .p,
            power: .off,
            speed: 0,
            physicalKeyInside: false,
            bleRssi: -52,
            phoneNearby: true
        )
    }

    /// 状态是否新鲜（默认 10 秒有效）
    func isFresh(maxAge: TimeInterval = 10) -> Bool {
        Date().timeIntervalSince(timestamp) <= maxAge
    }

    /// 手机是否远离（RSSI 低于阈值或信号丢失）
    var phoneFarAway: Bool {
        !phoneNearby
    }
}
