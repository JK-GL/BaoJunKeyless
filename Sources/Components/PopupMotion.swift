import SwiftUI

enum PopupMotion {
    /// 统一弹窗弹簧：比原来快一半，仍保留轻微弹性
    static let presentSpring = Animation.spring(response: 0.15, dampingFraction: 0.9)
    static let dismissEase = Animation.easeOut(duration: 0.16)
    static let contentEase = Animation.easeInOut(duration: 0.16)
    static let transition: AnyTransition = .scale.combined(with: .opacity)
}
