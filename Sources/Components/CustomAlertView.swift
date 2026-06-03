import SwiftUI

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
                    // 点击空白区域关闭
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isPresented = false } }

                    CustomAlertView(
                        title: title,
                        message: message,
                        confirmTitle: confirmTitle,
                        confirmColor: confirmColor,
                        onCancel: { withAnimation(.easeInOut(duration: 0.2)) { isPresented = false } },
                        onConfirm: {
                            withAnimation(.easeInOut(duration: 0.2)) { isPresented = false }
                            onConfirm()
                        }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

// MARK: - 自定义深色弹窗视图
struct CustomAlertView: View {
    let title: String
    let message: String
    let confirmTitle: String
    var confirmColor: Color = .red
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 24)

            // 消息
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)

            Divider()
                .background(Color.white.opacity(0.08))

            // 按钮
            HStack(spacing: 0) {
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .frame(height: 28)

                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(confirmColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 40, x: 0, y: 20)
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
