import SwiftUI

// MARK: - Menu Bar View (卡片统一圆角 24)
private let menuBarCornerRadius: CGFloat = 24

struct MenuBarView: View {
    // 导航切换动画放轻：过重 spring 会和状态页首帧渲染抢主线程。
    private static let tabSelectionAnimation = Animation.easeOut(duration: 0.16)

    @EnvironmentObject private var themeManager: ThemeManager
    @Binding var selectedTab: AppTab
    var navigationAnimation: Namespace.ID
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var theme: AppThemeConfiguration {
        themeManager.current
    }

    var body: some View {
        HStack(spacing: isCompactLayout ? 4 : 6) {
            ForEach(AppTab.mainNavigationTabs) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 1)
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

        shape
            .fill(.regularMaterial)
            .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private func tabClusterOutline() -> some View {
        EmptyView()
    }

    @ViewBuilder
    private func selectedTabBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: menuBarCornerRadius, style: .continuous)

        shape
            .fill(LinearGradient(colors: [theme.accent.opacity(0.22), theme.accent.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .matchedGeometryEffect(id: "tab-selection", in: navigationAnimation)
    }

    private var tabClusterShadowColor: Color {
        Color.black.opacity(0.08)
    }
}
