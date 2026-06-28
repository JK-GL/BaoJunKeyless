import SwiftUI

// MARK: - 统一悬浮弹窗底座
struct FloatingPopupCard<Content: View, Actions: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String = ""
    var maxWidth: CGFloat = 316
    var onClose: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.85)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 3)
                    .padding(.bottom, 12)
            } else {
                Spacer().frame(height: 10)
            }

            ScrollView(.vertical, showsIndicators: true) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)

            actions()
                .padding(.top, 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.38), radius: 34, x: 0, y: 16)
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, 24)
    }
}

// MARK: - 主按钮
struct FloatingPopupPrimaryButton: View {
    let title: String
    let color: Color
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var disabledBackgroundColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isDisabled ? (disabledBackgroundColor ?? Color.white.opacity(0.45)) : color)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - 次按钮
struct FloatingPopupSecondaryButton: View {
    let title: String
    var textColor: Color = Color.white.opacity(0.72)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.045))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
