import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .status
    @StateObject private var scrollState = AppScrollState()
    @Namespace private var tabAnimation

    var body: some View {
        ZStack(alignment: .top) {
            AppBackgroundView()

            tabContent(for: selectedTab)
                .transition(.opacity)
                .environmentObject(scrollState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        case .status:   StatusView()
        case .keyless:  KeylessView()
        case .logs:     LogView()
        case .settings: SettingsView()
        }
    }
}
