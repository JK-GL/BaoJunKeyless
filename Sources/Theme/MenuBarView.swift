import SwiftUI

// MARK: - Menu Bar View (卡片统一圆角 24)
private let menuBarCornerRadius: CGFloat = 24

struct MenuBarView: View {
    private static let tabSelectionAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)

    @AppStorage(AppThemePreset.storageKey) private var selectedThemeRawValue = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) private var customAccentData = Data()
    @Binding var selectedTab: AppTab
    var navigationAnimation: Namespace.ID
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var theme: AppThemeConfiguration {
        AppThemeConfiguration(
            selectedThemeRawValue: selectedThemeRawValue,
            customAccentData: customAccentData,
            customBackgroundRevision: 0
        )
    }

    var body: some View {
        HStack(spacing: isCompactLayout ? 4 : 6) {
            ForEach(AppTab.mainNavigationTabs) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, isCompactLayout ? 3 : 4)
        .frame(maxWidth: .infinity)
        .frame(height: menuBarHeight)
        .background(tabClusterBackground())
        .contentShape(RoundedRectangle(cornerRadius: menuBarCornerRadius, style: .continuous))
        .onTapGesture {}
        .overlay(tabClusterOutline())
        .shadow(color: tabClusterShadowColor, radius: 24, x: 0, y: 12)
        .animation(Self.tabSelectionAnimation, value: selectedTab)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            guard selectedTab != tab else { return }
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: isSelected ? 20 : 18, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: isCompactLayout ? 10 : 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: tabItemHeight)
            .background {
                if isSelected {
                    selectedTabBackground()
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layout Metrics

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var tabItemHeight: CGFloat {
        ChromeBarMetrics.tabItemHeight(for: horizontalSizeClass)
    }

    private var menuBarHeight: CGFloat {
        ChromeBarMetrics.menuBarHeight(for: horizontalSizeClass)
    }

    // MARK: - Backgrounds (与卡片 cornerRadius 24 + 描边统一)

    @ViewBuilder
    private func tabClusterBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: menuBarCornerRadius, style: .continuous)

        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .overlay { shape.fill(Color.primary).opacity(0.04) }
            } else {
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.15), .clear, Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    .overlay(shape.fill(Color.primary).opacity(0.02))
            }
        }
    }

    @ViewBuilder
    private func tabClusterOutline() -> some View {
        EmptyView()
    }

    @ViewBuilder
    private func selectedTabBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: menuBarCornerRadius, style: .continuous)

        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.fill(theme.accent).opacity(0.15))
            } else {
                shape
                    .fill(theme.accent).opacity(0.15)
                    .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 0.5))
            }
        }
        .matchedGeometryEffect(id: "tab-selection", in: navigationAnimation)
    }

    private var tabClusterShadowColor: Color {
        Color.black.opacity(0.08)
    }
}
