import SwiftUI

// MARK: - CardView (cornerRadius 24)
struct CardView<Content: View>: View {
    @EnvironmentObject var theme: ThemeManager
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
                    Text(title).font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - CollapsibleCard
struct CollapsibleCard<Header: View, Content: View>: View {
    @EnvironmentObject var theme: ThemeManager
    let title: String; let icon: String; let iconColor: Color
    @Binding var isExpanded: Bool
    let headerExtra: (() -> Header)?
    let content: () -> Content
    init(title: String, icon: String, iconColor: Color = .white,
         isExpanded: Binding<Bool>, @ViewBuilder headerExtra: @escaping () -> Header,
         @ViewBuilder content: @escaping () -> Content) {
        self.title=title; self.icon=icon; self.iconColor=iconColor
        self._isExpanded=isExpanded; self.headerExtra=headerExtra; self.content=content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.35)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundColor(iconColor).font(.system(size: 15, weight: .semibold))
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    Spacer()
                    headerExtra?()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }.buttonStyle(.plain)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().background(theme.cardStroke)
                    content()
                }.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
extension CollapsibleCard where Header == EmptyView {
    init(title: String, icon: String, iconColor: Color = .white,
         isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title=title; self.icon=icon; self.iconColor=iconColor
        self._isExpanded=isExpanded; self.headerExtra=nil; self.content=content
    }
}

// MARK: - StatusPill
struct StatusPill: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}

// MARK: - ToggleRow
struct ToggleRow: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String; let label: String; @Binding var isOn: Bool
    var body: some View {
        HStack {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.62)).frame(width: 22)
            Text(label).font(.system(size: 15)).foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(theme.accent)
        }
    }
}

// MARK: - SliderRow
struct SliderRow: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String; let label: String
    @Binding var value: Double; let range: ClosedRange<Double>; let step: Double
    let format: String; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.62))
                Text(label).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                Text(format).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            Slider(value: $value, in: range, step: step).tint(tint)
        }
    }
}

// MARK: - ChipButton
struct ChipButton: View {
    @EnvironmentObject var theme: ThemeManager
    let text: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? theme.accent : Color.white.opacity(0.10)))
        }
    }
}

// MARK: - InfoRow
struct InfoRow: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String; let label: String; let value: String
    var isMono: Bool = false; var valueColor: Color = .white
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.62)).frame(width: 20)
            Text(label).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.62))
            Spacer()
            Text(value).font(.system(size: isMono ? 12 : 13, weight: .medium, design: isMono ? .monospaced : .default))
                .foregroundColor(valueColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 2)
        Divider().background(Color.white.opacity(0.08)).padding(.leading, 30)
    }
}

// MARK: - SettingsRowView (XMusic: cornerRadius 18)
struct SettingsRowView: View {
    @EnvironmentObject var theme: ThemeManager
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Color.white.opacity(0.62))
            Spacer(minLength: 0)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - SectionTitleView (XMusic: .title2 .bold)
struct SectionTitleView: View {
    @EnvironmentObject var theme: ThemeManager
    let title: String; var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(.white)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(Color.white.opacity(0.62))
            }
        }
    }
}

// MARK: - DividerRow (XMusic: .leading 52)
struct DividerRow: View {
    @EnvironmentObject var theme: ThemeManager
    var body: some View {
        Divider().background(Color.white.opacity(0.08)).padding(.leading, 52)
    }
}

// MARK: - SettingsActionButton
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
            .background(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.3), lineWidth: 1))
        }
    }
}

// MARK: - ToastView
struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
            Text(text).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial).shadow(color: .black.opacity(0.1), radius: 10, y: 5))
    }
}
