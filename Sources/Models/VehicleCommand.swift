import Foundation

enum VehicleCommandKind: String, Codable {
    case lock
    case unlock
    case remoteStart
    case remoteStop
    case findCar
    case acOn
    case acOff
    case setTemperature
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

extension VehicleCommandKind {
    var supportsBLEControl: Bool {
        switch self {
        case .lock, .unlock, .remoteStart, .remoteStop:
            return true
        case .findCar, .acOn, .acOff, .setTemperature, .openWindows, .closeWindows, .quickCool:
            return false
        }
    }
}

struct VehicleCommand: Codable, Equatable {
    let kind: VehicleCommandKind
    let title: String
    let detail: String
    let requestedTemperature: Double?
    let requestedDurationMinutes: Int?
    let source: VehicleCommandSource
    let transportHint: VehicleCommandTransportHint

    init(
        kind: VehicleCommandKind,
        title: String,
        detail: String,
        requestedTemperature: Double?,
        source: VehicleCommandSource,
        transportHint: VehicleCommandTransportHint,
        requestedDurationMinutes: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.requestedTemperature = requestedTemperature
        self.requestedDurationMinutes = requestedDurationMinutes
        self.source = source
        self.transportHint = transportHint
    }
}

extension CommandAction {
    func asVehicleCommand(
        state: VehicleState,
        temperature: Double?,
        durationMinutes: Int? = nil,
        baselineTemperature: Double? = nil,
        source: VehicleCommandSource = .quickAction
    ) -> VehicleCommand {
        switch self {
        case .lockUnlock:
            if state.locked == false {
                return VehicleCommand(kind: .lock, title: "锁车", detail: "快捷操作锁车", requestedTemperature: nil, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .unlock, title: "解锁", detail: "快捷操作解锁", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .remoteStart:
            if state.power.isPoweredOn {
                return VehicleCommand(kind: .remoteStop, title: "远程熄火", detail: "快捷操作远程熄火", requestedTemperature: nil, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .remoteStart, title: "远程启动", detail: "快捷操作远程启动", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .findCar:
            return VehicleCommand(kind: .findCar, title: "寻车", detail: "快捷操作寻车", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .acToggle:
            if state.acOn == true {
                // 空调已开：
                // - 相对弹窗打开时的温度有变化 → 官方 status=5 设温
                // - 温度未变化 → 官方 status=7 关空调
                // 用弹窗初值而不是仅 state.acTemperature，避免车况温度缺失/滞后导致滑条改温仍发“关闭”。
                let requested = temperature.map { Int($0.rounded()) }
                let baseline = (baselineTemperature ?? state.acTemperature).map { Int($0.rounded()) }
                if let requested, baseline == nil || requested != baseline {
                    return VehicleCommand(
                        kind: .setTemperature,
                        title: "设定温度",
                        detail: "快捷操作设定温度 \(requested)°C",
                        requestedTemperature: Double(requested),
                        source: source,
                        transportHint: .httpControl
                    )
                }
                return VehicleCommand(kind: .acOff, title: "关闭空调", detail: "快捷操作关闭空调", requestedTemperature: temperature, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .acOn, title: "开启空调", detail: "快捷操作开启空调", requestedTemperature: temperature, source: source, transportHint: .httpControl)
        case .windowToggle:
            if state.windowsClosed == false {
                return VehicleCommand(kind: .closeWindows, title: "关闭车窗", detail: "快捷操作关闭车窗", requestedTemperature: nil, source: source, transportHint: .httpControl)
            }
            return VehicleCommand(kind: .openWindows, title: "打开车窗", detail: "快捷操作打开车窗", requestedTemperature: nil, source: source, transportHint: .httpControl)
        case .quickCool:
            return VehicleCommand(kind: .quickCool, title: "快速降温", detail: "快捷操作快速降温", requestedTemperature: temperature ?? 17, source: source, transportHint: .httpControl, requestedDurationMinutes: durationMinutes ?? 10)
        }
    }
}
