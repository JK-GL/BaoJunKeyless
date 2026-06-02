import SwiftUI

// MARK: - Card (XMusic style)
struct CardView<Content: View>: View {
    let title: String?
    let icon: String?
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, icon: String? = nil, iconColor: Color = .white,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.icon = icon; self.iconColor = iconColor; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon).foregroundColor(iconColor)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeColors.textPrimary)
                }
            }
            content()
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
        .padding(.horizontal, 16)
    }
}

// MARK: - Collapsible Card
struct CollapsibleCard<Header: View, Content: View>: View {
    let title: String; let icon: String; let iconColor: Color
    @Binding var isExpanded: Bool
    let headerExtra: (() -> Header)?
    let content: () -> Content

    init(title: String, icon: String, iconColor: Color = .white,
         isExpanded: Binding<Bool>,
         @ViewBuilder headerExtra: @escaping () -> Header,
         @ViewBuilder content: @escaping () -> Content) {
        self.title=title; self.icon=icon; self.iconColor=iconColor
        self._isExpanded=isExpanded; self.headerExtra=headerExtra; self.content=content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.35)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundColor(iconColor)
                        .font(.system(size: 15, weight: .semibold))
                    Text(title).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeColors.textPrimary)
                    Spacer()
                    headerExtra?()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ThemeColors.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().background(ThemeColors.cardStroke)
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ThemeColors.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ThemeColors.cardStroke, lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

extension CollapsibleCard where Header == EmptyView {
    init(title: String, icon: String, iconColor: Color = .white,
         isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title=title; self.icon=icon; self.iconColor=iconColor
        self._isExpanded=isExpanded; self.headerExtra=nil; self.content=content
    }
}

// MARK: - Status Pill
struct StatusPill: View {
    let icon: String; let text: String; let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(ThemeColors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}

// MARK: - Toggle Row
struct ToggleRow: View {
    let icon: String; let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(ThemeColors.textSecondary).frame(width: 22)
            Text(label).font(.system(size: 15)).foregroundStyle(ThemeColors.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
                .tint(ThemeColors.accent)
        }
    }
}

// MARK: - Slider Row
struct SliderRow: View {
    let icon: String; let label: String
    @Binding var value: Double; let range: ClosedRange<Double>; let step: Double
    let format: String; let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(ThemeColors.textSecondary)
                Text(label).font(.system(size: 14)).foregroundStyle(ThemeColors.textSecondary)
                Spacer()
                Text(format).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ThemeColors.textSecondary)
            }
            Slider(value: $value, in: range, step: step).tint(tint)
        }
    }
}

// MARK: - Chip Button
struct ChipButton: View {
    let text: String; let isSelected: Bool; let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : ThemeColors.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? ThemeColors.accent : ThemeColors.pillBg))
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String; let label: String; let value: String
    var isMono: Bool = false; var valueColor: Color = .white

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(ThemeColors.textSecondary).frame(width: 20)
            Text(label).font(.system(size: 14)).foregroundStyle(ThemeColors.textSecondary)
            Spacer()
            Text(value).font(.system(size: isMono ? 12 : 13, weight: .medium, design: isMono ? .monospaced : .default))
                .foregroundColor(valueColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 2)
        Divider().background(ThemeColors.cardStroke).padding(.leading, 30)
    }
}

// MARK: - Settings Action Button
struct SettingsActionButton: View {
    let icon: String; let label: String; let color: Color; let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1))
        }
    }
}

// MARK: - Toast
struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(ThemeColors.accent)
            Text(text).font(.system(size: 14, weight: .medium))
                .foregroundStyle(ThemeColors.textPrimary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial).shadow(color: .black.opacity(0.1), radius: 10, y: 5))
    }
}
