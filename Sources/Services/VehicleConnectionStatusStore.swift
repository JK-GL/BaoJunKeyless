import Foundation
import Combine

final class VehicleConnectionStatusStore: ObservableObject {
    static let shared = VehicleConnectionStatusStore()

    enum LiveBLEStatus: Equatable {
        case disconnected
        case scanning
        /// 仅围栏内扫描开启且当前在围栏外：自动扫描休眠
        case pausedOutsideFence
        case connecting
        case connected
        case authenticating
        case authenticated
        case error
    }

    enum LiveMQTTStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error
    }

    @Published var bleStatus: LiveBLEStatus = .disconnected
    /// 系统层是否已存在目标车 BLE 连接（retrieveConnected / peripheral.state==.connected）
    @Published var isSystemBLEConnected: Bool = false
    @Published var mqttStatus: LiveMQTTStatus = .disconnected
    @Published var authStatus: StatusAuthState = .expired("未登录")

    var uiBLEStatus: StatusBLEState {
        switch bleStatus {
        case .authenticated: return .authenticated
        case .authenticating: return .authenticating
        case .connected: return .connected
        case .connecting:
            // 系统未连上时，不要显示“连接中”误导；显示扫描/寻找
            return isSystemBLEConnected ? .connecting : .scanning
        case .scanning: return .scanning
        case .pausedOutsideFence: return .pausedOutsideFence
        case .error: return .error
        case .disconnected: return .disconnected
        }
    }

    var uiMQTTStatus: StatusMQTTState {
        switch mqttStatus {
        case .connected: return .connected
        case .connecting: return .connecting
        case .error: return .error
        case .disconnected: return .disconnected
        }
    }
}
