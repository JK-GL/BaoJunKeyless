import SwiftUI

enum PopupMotion {
    static let presentSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let dismissEase = Animation.easeOut(duration: 0.2)
    static let contentEase = Animation.easeInOut(duration: 0.2)
    static let transition: AnyTransition = .scale.combined(with: .opacity)
}
