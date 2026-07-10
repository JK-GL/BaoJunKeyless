import SwiftUI
import UIKit

enum AppHaptics {
    static func light() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()
    }

    static func medium() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
    }
}

struct ResponsiveButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97
    var pressedOpacity: Double = 0.8
    var playsHaptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed, playsHaptic {
                    AppHaptics.light()
                }
            }
    }
}

// MARK: - CardView
struct CardView<Content: View>: View {
    @EnvironmentObject var theme: ThemeManager
    let title: String?
    let icon: String?
    let iconColor: Color
    let headerAccessory: AnyView?
    @ViewBuilder let content: () -> Content
    init(title: String? = nil, icon: String? = nil, iconColor: Color = .white,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.headerAccessory = nil
        self.content = content
    }

    init<Accessory: View>(title: String? = nil, icon: String? = nil, iconColor: Color = .white,
                          @ViewBuilder headerAccessory: @escaping () -> Accessory,
                          @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.headerAccessory = AnyView(headerAccessory())
        self.content = content
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
                    if let headerAccessory {
                        Spacer(minLength: 8)
                        headerAccessory
                    }
                }
            }
            content()
        }
        .padding(AppSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppSurface.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(AppSurface.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)
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
            Button(action: { withAnimation(PopupMotion.contentEase) { isExpanded.toggle() } }) {
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
        .padding(AppSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppSurface.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(AppSurface.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)
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
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .imageScale(.small)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.18))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
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
    var onEditingEnded: ((Double) -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.62))
                Text(label).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                Text(format).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            Slider(value: $value, in: range, step: step) { editing in
                if !editing { onEditingEnded?(value) }
            }
            .tint(tint)
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
        .buttonStyle(ResponsiveButtonStyle())
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
        .background(AppSurface.controlFill, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous).stroke(AppSurface.controlStroke, lineWidth: 1))
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
            .background(RoundedRectangle(cornerRadius: AppRadius.control).stroke(color.opacity(0.3), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control))
        }
        .buttonStyle(ResponsiveButtonStyle())
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
