import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .status
    @StateObject private var scrollState = AppScrollState()
    @Namespace private var tabAnimation

    var body: some View {
        ZStack(alignment: .top) {
            AppBackgroundView()

            // 状态页常驻：官方 App 同类做法，避免每次点导航都销毁/重建整页导致迟钝。
            // 其它页按需创建，节省内存。
            StatusView()
                .environmentObject(scrollState)
                .opacity(selectedTab == .status ? 1 : 0)
                .allowsHitTesting(selectedTab == .status)
                .zIndex(selectedTab == .status ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if selectedTab != .status {
                secondaryTabContent(for: selectedTab)
                    .environmentObject(scrollState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .zIndex(2)
            }
        }
        .appOnChange(of: selectedTab) {
            // 离开状态页时重置滚动跟踪；状态页本身保留，不重建。
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
