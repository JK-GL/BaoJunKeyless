import SwiftUI

// MARK: - App Design Tokens
// 统一收口常用圆角、间距、透明度和基础表面色，避免 UI 样式散落在各个视图里。

enum AppRadius {
    static let card: CGFloat = 24
    static let section: CGFloat = 18
    static let control: CGFloat = 18
    static let compactControl: CGFloat = 14
    static let segmented: CGFloat = 16
}

enum AppSpacing {
    static let cardPadding: CGFloat = 16
    static let panelPadding: CGFloat = 14
    static let screenHorizontal: CGFloat = 18
    static let section: CGFloat = 12
    static let compact: CGFloat = 8
}

enum AppOpacity {
    static let cardFill: Double = 0.06
    static let cardStroke: Double = 0.08
    static let sectionFill: Double = 0.04
    static let sectionStroke: Double = 0.06
    static let controlFill: Double = 0.045
    static let controlStroke: Double = 0.05
    static let subtleText: Double = 0.62
}

enum AppSurface {
    static var cardFill: Color { Color.white.opacity(AppOpacity.cardFill) }
    static var cardStroke: Color { Color.white.opacity(AppOpacity.cardStroke) }
    static var sectionFill: Color { Color.white.opacity(AppOpacity.sectionFill) }
    static var sectionStroke: Color { Color.white.opacity(AppOpacity.sectionStroke) }
    static var controlFill: Color { Color.white.opacity(AppOpacity.controlFill) }
    static var controlStroke: Color { Color.white.opacity(AppOpacity.controlStroke) }
    static var subtleText: Color { Color.white.opacity(AppOpacity.subtleText) }
}
