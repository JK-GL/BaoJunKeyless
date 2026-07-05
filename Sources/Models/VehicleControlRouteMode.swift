import Foundation

enum VehicleControlRouteMode: String, CaseIterable, Codable {
    case auto
    case forceBLE
    case forceHTTP

    var title: String {
        switch self {
        case .auto: return "自动"
        case .forceBLE: return "强制BLE"
        case .forceHTTP: return "强制HTTP"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "BLE 已鉴权时优先 BLE，否则走 HTTP。"
        case .forceBLE: return "只走 BLE，适合复现蓝牙连接/回包问题。"
        case .forceHTTP: return "只走 HTTP，适合对比云控链路。"
        }
    }
}
