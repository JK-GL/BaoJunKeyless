import SwiftUI
import UIKit

// MARK: - 自定义深色弹窗修饰符
struct DarkAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirmTitle: String
    var confirmColor: Color = .red
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(PopupMotion.dismissEase) { isPresented = false } }

                    CustomAlertView(
                        title: title,
                        message: message,
                        confirmTitle: confirmTitle,
                        confirmColor: confirmColor,
                        onCancel: { withAnimation(PopupMotion.dismissEase) { isPresented = false } },
                        onConfirm: {
                            withAnimation(PopupMotion.dismissEase) { isPresented = false }
                            onConfirm()
                        }
                    )
                    .transition(PopupMotion.transition)
                }
            }
            .animation(PopupMotion.presentSpring, value: isPresented)
    }
}

// MARK: - 自定义统一悬浮弹窗视图
struct CustomAlertView: View {
    let title: String
    let message: String
    let confirmTitle: String
    var confirmColor: Color = .red
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        FloatingPopupCard(
            icon: "exclamationmark.triangle.fill",
            iconColor: confirmColor,
            title: title,
            subtitle: message
        ) {
            EmptyView()
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(
                    title: confirmTitle,
                    color: confirmColor,
                    action: onConfirm
                )

                FloatingPopupSecondaryButton(
                    title: "取消",
                    textColor: Color.white.opacity(0.62),
                    action: onCancel
                )
            }
        }
    }
}

// MARK: - View 扩展方便调用
extension View {
    func darkAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmTitle: String = "确认",
        confirmColor: Color = .red,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DarkAlertModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            confirmColor: confirmColor,
            onConfirm: onConfirm
        ))
    }
}
