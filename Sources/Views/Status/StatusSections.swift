import SwiftUI

enum StatusAuthState {
    case valid
    case expired(String)

    var color: Color {
        switch self {
        case .valid: return AppTheme.green
        case .expired: return AppTheme.red
        }
    }

    var text: String? {
        switch self {
        case .valid: return nil
        case .expired(let message): return message
        }
    }
}

enum StatusBLEState: Equatable {
    case disconnected
    case scanning
    case connected
    case weak
    case error

    var icon: String {
        switch self {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .disconnected, .scanning, .weak, .error: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var text: String {
        switch self {
        case .disconnected: return "BLE未连接"
        case .scanning: return "BLE扫描中"
        case .connected: return "BLE已连接"
        case .weak: return "BLE信号弱"
        case .error: return "BLE异常"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return Color.white.opacity(0.45)
        case .scanning: return AppTheme.accent
        case .connected: return AppTheme.green
        case .weak: return AppTheme.orange
        case .error: return AppTheme.red
        }
    }
}

enum StatusMQTTState: Equatable {
    case disconnected
    case connecting
    case connected
    case error

    var icon: String {
        switch self {
        case .connected: return "antenna.radiowaves.left.and.right.circle.fill"
        case .connecting: return "dot.radiowaves.left.and.right"
        case .disconnected, .error: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var text: String {
        switch self {
        case .disconnected: return "MQTT未连接"
        case .connecting: return "MQTT连接中"
        case .connected: return "MQTT已连接"
        case .error: return "MQTT异常"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return Color.white.opacity(0.45)
        case .connecting: return AppTheme.accent
        case .connected: return AppTheme.green
        case .error: return AppTheme.red
        }
    }
}

enum StatusDoorLockState {
    case locked
    case unlocked
    case unknown

    var icon: String {
        switch self {
        case .locked: return "lock.fill"
        case .unlocked: return "lock.open.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var text: String {
        switch self {
        case .locked: return "已锁车"
        case .unlocked: return "已解锁"
        case .unknown: return "车锁未知"
        }
    }

    var color: Color {
        switch self {
        case .locked: return AppTheme.green
        case .unlocked: return AppTheme.orange
        case .unknown: return Color.white.opacity(0.45)
        }
    }
}

enum StatusPhysicalKeyState {
    case normal
    case inCar
    case unknown

    var icon: String { "key.fill" }

    var text: String {
        switch self {
        case .normal: return "钥匙正常"
        case .inCar: return "钥匙在车"
        case .unknown: return "钥匙未知"
        }
    }

    var color: Color {
        switch self {
        case .normal: return AppTheme.green
        case .inCar: return AppTheme.orange
        case .unknown: return Color.white.opacity(0.45)
        }
    }
}

enum StatusGearState {
    case park
    case reverse
    case neutral
    case drive
    case unknown

    var icon: String { "gearshape.fill" }

    var text: String {
        switch self {
        case .park: return "P挡"
        case .reverse: return "R挡"
        case .neutral: return "N挡"
        case .drive: return "D挡"
        case .unknown: return "档位未知"
        }
    }

    var color: Color {
        switch self {
        case .park: return AppTheme.green
        case .reverse: return AppTheme.red
        case .neutral: return AppTheme.orange
        case .drive: return AppTheme.red
        case .unknown: return Color.white.opacity(0.45)
        }
    }
}

struct StatusTopBarSection: View {
    let vehicleName: String
    let isRefreshing: Bool
    let refreshScale: CGFloat
    let authStatus: StatusAuthState
    let onRefresh: () -> Void

    init(
        vehicleName: String = "宝骏云海",
        isRefreshing: Bool,
        refreshScale: CGFloat,
        authStatus: StatusAuthState = .valid,
        onRefresh: @escaping () -> Void
    ) {
        self.vehicleName = vehicleName
        self.isRefreshing = isRefreshing
        self.refreshScale = refreshScale
        self.authStatus = authStatus
        self.onRefresh = onRefresh
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(vehicleName)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            AuthStatusBadge(authStatus: authStatus)

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: isRefreshing ? "hourglass" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .frame(width: 20, height: 20)
                    .scaleEffect(refreshScale)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }
}

private struct AuthStatusBadge: View {
    let authStatus: StatusAuthState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: authStatus.text == nil ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
            if let text = authStatus.text {
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(authStatus.color)
    }
}

struct StatusPillsSection: View {
    let modeIcon: String
    let modeText: String
    let modeColor: Color
    var bleStatus: StatusBLEState = .connected
    var mqttStatus: StatusMQTTState = .disconnected
    var doorLockState: StatusDoorLockState = .locked
    var physicalKeyState: StatusPhysicalKeyState = .normal
    var gearState: StatusGearState = .park

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                StatusPill(icon: bleStatus.icon, text: bleStatus.text, color: bleStatus.color)
                StatusPill(icon: mqttStatus.icon, text: mqttStatus.text, color: mqttStatus.color)
                StatusPill(icon: modeIcon, text: modeText, color: modeColor)
                StatusPill(icon: doorLockState.icon, text: doorLockState.text, color: doorLockState.color)
                StatusPill(icon: physicalKeyState.icon, text: physicalKeyState.text, color: physicalKeyState.color)
                StatusPill(icon: gearState.icon, text: gearState.text, color: gearState.color)
            }
            .padding(.horizontal, 20)
        }
    }
}

extension StatusGearState {
    init(gear: VehicleGear) {
        switch gear {
        case .p: self = .park
        case .r: self = .reverse
        case .n: self = .neutral
        case .d: self = .drive
        case .unknown: self = .unknown
        }
    }
}
