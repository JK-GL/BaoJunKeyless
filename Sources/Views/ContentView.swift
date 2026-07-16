import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .status
    @StateObject private var scrollState = AppScrollState()
    @Namespace private var tabAnimation

    var body: some View {
        ZStack(alignment: .top) {
            AppBackgroundView()

            // 单页切换：避免状态页常驻后台继续重绘，导致整 App 发黏。
            tabContent(for: selectedTab)
                .environmentObject(scrollState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(selectedTab)
        }
        .appOnChange(of: selectedTab) {
            scrollState.reset()
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
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .status:
            StatusView()
        case .keyless:
            KeylessView()
        case .logs:
            LogView()
        case .settings:
            SettingsView()
        }
    }
}
