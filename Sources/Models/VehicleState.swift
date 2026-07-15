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
        case .unknown: return "--"
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
        case .off:     return "熄火"
        case .acc:     return "ACC"
        case .on:      return "上电"
        case .ready:   return "Ready"
        case .unknown: return "未知"
        }
    }

    /// 是否已处于上电/可驾驶相关态（用于远程启动按钮切换）
    var isPoweredOn: Bool {
        self == .on || self == .ready
    }

    /// 远程启动弹窗「启动」列文案
    var remoteStartStatusTitle: String {
        switch self {
        case .on:      return "上电"
        case .ready:   return "Ready"
        case .acc:     return "ACC"
        case .off, .unknown:
            return "待授权"
        }
    }
}

enum PhysicalKeyPosition: String, Codable, CaseIterable {
    case farAway
    case outside
    case inside
    case unknown
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

    // 油量信号字段（用于能源类型检测）
    var fuelRange: Double? = nil
    var fuelLevel: Double? = nil
    var oilRange: Double? = nil

    var acOn: Bool?
    var acTemperature: Double?
    var gear: VehicleGear
    var power: VehiclePowerState
    var speed: Double?
    var physicalKeyPosition: PhysicalKeyPosition = .unknown
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
            fuelRange: nil,
            fuelLevel: nil,
            oilRange: nil,
            acOn: nil,
            acTemperature: nil,
            gear: .unknown,
            power: .unknown,
            speed: nil,
            physicalKeyPosition: .unknown,
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
            windowsClosed: true,
            fuelRange: 680,
            fuelLevel: 85,
            oilRange: 680,
            acOn: false,
            acTemperature: 22,
            gear: .p,
            power: .off,
            speed: 0,
            physicalKeyPosition: .outside,
            bleRssi: -52,
            phoneNearby: true
        )
    }

    /// 状态是否新鲜（默认 90 秒，覆盖 HTTP 60s 轮询 + 余量）
    func isFresh(maxAge: TimeInterval = 90) -> Bool {
        Date().timeIntervalSince(timestamp) <= maxAge
    }

    /// 是否具备可用的 live BLE 靠近判定（仅信手机侧 RSSI，不信 HTTP keyStatus）
    var hasLiveBLEProximity: Bool {
        bleRssi != nil
    }

    /// 手机是否远离（RSSI 低于阈值或信号丢失）
    var phoneFarAway: Bool {
        !phoneNearby
    }
}
