import SwiftUI

struct ContentView: View {
    private static let tabSwitchAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)

    @State private var selectedTab: AppTab = .status
    @StateObject private var scrollState = AppScrollState()
    @Namespace private var tabAnimation

    var body: some View {
        ZStack(alignment: .top) {
            AppBackgroundView()

            tabContent(for: selectedTab)
                .id(selectedTab)
                .transition(.opacity)
                .environmentObject(scrollState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(Self.tabSwitchAnimation, value: selectedTab)
        .appOnChange(of: selectedTab) {
            scrollState.reset()
        }
        .safeAreaInset(edge: .bottom) {
            MenuBarView(
                selectedTab: $selectedTab,
                navigationAnimation: tabAnimation
            )
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, -8.0)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .status:   StatusView()
        case .keyless:  KeylessView()
        case .logs:     LogView()
        case .settings: SettingsView()
        }
    }
}
