import SwiftUI

// MARK: - App Tab Definition
enum AppTab: String, CaseIterable, Identifiable {
    case status
    case keyless
    case logs
    case settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .status:   return "car.fill"
        case .keyless:  return "dot.radiowaves.left.and.right"
        case .logs:     return "list.bullet.rectangle"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .status:   return "状态"
        case .keyless:  return "无感"
        case .logs:     return "日志"
        case .settings: return "设置"
        }
    }

    static var mainNavigationTabs: [AppTab] {
        [.status, .keyless, .logs, .settings]
    }
}

// MARK: - Chrome Bar Metrics
enum ChromeBarMetrics {
    static func menuBarHeight(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .compact ? 44 : 46
    }

    static func tabItemHeight(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        menuBarHeight(for: sizeClass) - 5
    }

    static func compactChromeHeight(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .compact ? 36 : 38
    }
}
