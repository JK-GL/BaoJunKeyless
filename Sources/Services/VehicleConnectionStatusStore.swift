import Foundation
import Combine

final class VehicleConnectionStatusStore: ObservableObject {
    static let shared = VehicleConnectionStatusStore()

    enum LiveBLEStatus: Equatable {
        case disconnected
        case scanning
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
    @Published var mqttStatus: LiveMQTTStatus = .disconnected
    @Published var authStatus: StatusAuthState = .expired("未登录")

    var uiBLEStatus: StatusBLEState {
        switch bleStatus {
        case .authenticated: return .authenticated
        case .authenticating: return .authenticating
        case .connected: return .connected
        case .connecting: return .connecting
        case .scanning: return .scanning
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
