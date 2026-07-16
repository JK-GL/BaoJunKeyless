import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .status
    @StateObject private var scrollState = AppScrollState()
    @Namespace private var tabAnimation

    private var isStatusVisible: Bool {
        selectedTab == .status
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackgroundView()

            // 状态页：首次创建后常驻，离开时冻结雷达动画，避免每次导航整页重建。
            StatusView(isPageVisible: isStatusVisible)
                .environmentObject(scrollState)
                .opacity(isStatusVisible ? 1 : 0)
                .allowsHitTesting(isStatusVisible)
                .zIndex(isStatusVisible ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !isStatusVisible {
                secondaryTabContent(for: selectedTab)
                    .environmentObject(scrollState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(2)
            }
        }
        .appOnChange(of: selectedTab) {
            // 离开状态页时只重置滚动跟踪；状态页本身不销毁。
            if selectedTab != .status {
                scrollState.reset()
            }
        }
        .safeAreaInset(edge: .bottom) {
            MenuBarView(
                selectedTab: $selectedTab,
                navigationAnimation: tabAnimation
            )
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, -8.0)
        }
    }

    @ViewBuilder
    private func secondaryTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .status:
            EmptyView()
        case .keyless:
            KeylessView()
        case .logs:
            LogView()
        case .settings:
            SettingsView()
        }
    }
}
