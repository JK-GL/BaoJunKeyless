import Foundation

enum VehicleCommandKind: String, Codable {
    case lock
    case unlock
    case remoteStart
    case remoteStop
    case findCar
    case acOn
    case acOff
    case openWindows
    case closeWindows
    case quickCool
}

enum VehicleCommandSource: String, Codable {
    case quickAction
    case keyless
}

enum VehicleCommandTransportHint: String, Codable {
    case unknown
    case mqttControl
    case httpControl
    case bleControl
}

struct VehicleCommand: Codable, Equatable {
    let kind: VehicleCommandKind
    let title: String
    let detail: String
    let requestedTemperature: Double?
    let source: VehicleCommandSource
    let transportHint: VehicleCommandTransportHint
}

extension CommandAction {
    func asVehicleCommand(
        state: VehicleState,
        temperature: Double?,
        source: VehicleCommandSource = .quickAction
    ) -> VehicleCommand {
        switch self {
        case .lockUnlock:
            if state.locked == false {
                return VehicleCommand(kind: .lock, title: "锁车", detail: "快捷操作锁车", requestedTemperature: nil, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .unlock, title: "解锁", detail: "快捷操作解锁", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .remoteStart:
            if state.power == .on || state.power == .ready {
                return VehicleCommand(kind: .remoteStop, title: "远程熄火", detail: "快捷操作远程熄火", requestedTemperature: nil, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .remoteStart, title: "远程启动", detail: "快捷操作远程启动", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .findCar:
            return VehicleCommand(kind: .findCar, title: "寻车", detail: "快捷操作寻车", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .acToggle:
            if state.acOn == true {
                return VehicleCommand(kind: .acOff, title: "关闭空调", detail: "快捷操作关闭空调", requestedTemperature: temperature, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .acOn, title: "开启空调", detail: "快捷操作开启空调", requestedTemperature: temperature, source: source, transportHint: .httpControl)
        case .windowToggle:
            if state.windowsClosed == false {
                return VehicleCommand(kind: .closeWindows, title: "关闭车窗", detail: "快捷操作关闭车窗", requestedTemperature: nil, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .openWindows, title: "打开车窗", detail: "快捷操作打开车窗", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .quickCool:
            return VehicleCommand(kind: .quickCool, title: "快速降温", detail: "快捷操作快速降温", requestedTemperature: temperature ?? 17, source: source, transportHint: .httpControl)
        }
    }
}
