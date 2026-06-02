import SwiftUI

struct SettingsPanelView<Content: View>: View {
    let title: String
    var subtitle: String = ""
    let content: Content

    init(title: String, subtitle: String = "", @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(ThemeColors.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ThemeColors.textSecondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ThemeColors.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ThemeColors.cardStroke, lineWidth: 1)
        )
    }
}
