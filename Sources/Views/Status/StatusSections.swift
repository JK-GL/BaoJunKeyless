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
    /// 仅围栏内扫描 · 当前围栏外，自动扫描休眠
    case pausedOutsideFence
    case connecting
    case connected
    case authenticating
    case authenticated
    case weak
    case error

    var icon: String {
        switch self {
        case .authenticated: return "checkmark.seal.fill"
        case .connected: return "link.circle.fill"
        case .connecting, .authenticating: return "dot.radiowaves.left.and.right"
        case .pausedOutsideFence: return "location.slash"
        case .disconnected, .scanning, .weak, .error: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var text: String {
        switch self {
        case .disconnected: return "BLE未连接"
        case .scanning: return "BLE扫描中"
        case .pausedOutsideFence: return "BLE围栏外休眠"
        // connecting = App 正在连，但系统未必已连上；文案用“寻找/连接中”避免误解成“已连上”
        case .connecting: return "BLE连接中"
        case .connected: return "BLE链路中"
        case .authenticating: return "BLE鉴权中"
        case .authenticated: return "BLE已连接"
        case .weak: return "BLE信号弱"
        case .error: return "BLE异常"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return Color.white.opacity(0.45)
        case .pausedOutsideFence: return AppTheme.orange
        case .scanning, .connecting: return AppTheme.accent
        case .connected: return AppTheme.green.opacity(0.82)
        case .authenticating: return AppTheme.orange
        case .authenticated: return AppTheme.green
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
        case .connected: return "antenna.radiowaves.left.and.right"
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
    case farAway
    case outside
    /// 在线新鲜且无手机数字钥匙会话时，云端 inside 才提示“感应车内”
    case inCar
    /// 手机数字钥匙会话下的 inside，或云端 inside 但更像手机钥匙
    case digitalNearby
    case unknown

    var icon: String {
        switch self {
        case .digitalNearby: return "wave.3.right"
        default: return "key.fill"
        }
    }

    var text: String {
        switch self {
        case .farAway: return "钥匙远离"
        case .outside: return "钥匙车外"
        // 不再写“物理钥匙”，避免把数字钥匙误报当成实体钥匙
        case .inCar: return "感应车内"
        case .digitalNearby: return "数字钥匙附近"
        case .unknown: return "钥匙未知"
        }
    }

    var color: Color {
        switch self {
        case .farAway: return Color.white.opacity(0.45)
        case .outside: return AppTheme.green
        case .inCar: return AppTheme.orange
        case .digitalNearby: return AppTheme.accent
        case .unknown: return Color.white.opacity(0.45)
        }
    }

    /// 云端 keyStatus 不可靠：
    /// - BLE 已鉴权 / 有 live RSSI：inside 当数字钥匙
    /// - 离线 / 车况过期：不展示“钥匙车内/物理钥匙”，回落未知
    /// - 仅在线且新鲜、又无手机 BLE 会话时，才显示感应车内
    static func from(
        position: PhysicalKeyPosition,
        bleAuthenticated: Bool,
        online: Bool = true,
        isFresh: Bool = true,
        hasLiveBLE: Bool = false
    ) -> StatusPhysicalKeyState {
        switch position {
        case .farAway: return .farAway
        case .outside: return .outside
        case .inside:
            if bleAuthenticated || hasLiveBLE {
                return .digitalNearby
            }
            if !online || !isFresh {
                return .unknown
            }
            return .inCar
        case .unknown:
            return .unknown
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

struct StatusTopBarSection: View, Equatable {
    let vehicleName: String
    let isRefreshing: Bool
    let refreshScale: CGFloat
    let authStatus: StatusAuthState
    let onRefresh: () -> Void

    static func == (lhs: StatusTopBarSection, rhs: StatusTopBarSection) -> Bool {
        lhs.vehicleName == rhs.vehicleName
            && lhs.isRefreshing == rhs.isRefreshing
            && lhs.refreshScale == rhs.refreshScale
            && lhs.authStatusText == rhs.authStatusText
    }

    private var authStatusText: String {
        switch authStatus {
        case .valid:
            return "valid"
        case .expired(let message):
            return "expired|\(message)"
        }
    }

    init(
        vehicleName: String = "车辆状态",
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

            Spacer(minLength: 8)

            // 一点立即沙漏，完成后回箭头；箭头尺寸恢复旧版。
            Button {
                AppHaptics.light()
                onRefresh()
            } label: {
                Image(systemName: isRefreshing ? "hourglass" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                    .frame(width: 20, height: 20)
                    .scaleEffect(refreshScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ResponsiveButtonStyle(playsHaptic: false))
            .layoutPriority(2)
            .accessibilityLabel(isRefreshing ? "正在刷新" : "刷新车况")
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

struct StatusPillsSection: View, Equatable {
    let modeIcon: String
    let modeText: String
    let modeColor: Color
    var bleStatus: StatusBLEState = .authenticated
    var mqttStatus: StatusMQTTState = .disconnected
    var showsMQTT: Bool = true
    var physicalKeyState: StatusPhysicalKeyState = .outside
    var gearState: StatusGearState = .park
    var onBLETap: (() -> Void)? = nil
    var onMQTTTap: (() -> Void)? = nil

    static func == (lhs: StatusPillsSection, rhs: StatusPillsSection) -> Bool {
        lhs.modeIcon == rhs.modeIcon
            && lhs.modeText == rhs.modeText
            && lhs.bleStatus == rhs.bleStatus
            && lhs.mqttStatus == rhs.mqttStatus
            && lhs.showsMQTT == rhs.showsMQTT
            && lhs.physicalKeyState.text == rhs.physicalKeyState.text
            && lhs.gearState.text == rhs.gearState.text
    }

    private var compactPhysicalKeyText: String {
        switch physicalKeyState {
        case .farAway: return "钥匙远离"
        case .outside: return "钥匙车外"
        case .inCar: return "感应车内"
        case .digitalNearby: return "数字钥匙"
        case .unknown: return "钥匙未知"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let onBLETap {
                    Button {
                        AppHaptics.light()
                        onBLETap()
                    } label: {
                        StatusPill(icon: bleStatus.icon, text: bleStatus.text, color: bleStatus.color)
                    }
                    .buttonStyle(ResponsiveButtonStyle(playsHaptic: false))
                } else {
                    StatusPill(icon: bleStatus.icon, text: bleStatus.text, color: bleStatus.color)
                }
                if showsMQTT {
                    if let onMQTTTap {
                        Button {
                            AppHaptics.light()
                            onMQTTTap()
                        } label: {
                            StatusPill(icon: mqttStatus.icon, text: mqttStatus.text, color: mqttStatus.color)
                        }
                        .buttonStyle(ResponsiveButtonStyle(playsHaptic: false))
                    } else {
                        StatusPill(icon: mqttStatus.icon, text: mqttStatus.text, color: mqttStatus.color)
                    }
                }
                StatusPill(icon: modeIcon, text: modeText, color: modeColor)
                StatusPill(icon: physicalKeyState.icon, text: compactPhysicalKeyText, color: physicalKeyState.color)
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
