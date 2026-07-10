import SwiftUI

enum PopupMotion {
    /// 统一弹窗弹簧：再减半，接近系统 sheet 的轻快手感
    static let presentSpring = Animation.spring(response: 0.08, dampingFraction: 0.92)
    static let dismissEase = Animation.easeOut(duration: 0.12)
    static let contentEase = Animation.easeInOut(duration: 0.12)
    /// 轻量过渡：缩放幅度小，减少毛玻璃合成成本
    static let transition: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.96)),
        removal: .opacity.combined(with: .scale(scale: 0.98))
    )
}
