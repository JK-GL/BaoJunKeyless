import SwiftUI

struct ContentView: View {
    private static let tabSwitchAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)

    @State private var selectedTab: AppTab = .status
    @Namespace private var tabAnimation

    var body: some View {
        ZStack(alignment: .top) {
            AppBackgroundView()

            tabContent(for: selectedTab)
                .id(selectedTab)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(Self.tabSwitchAnimation, value: selectedTab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MenuBarView(
                selectedTab: $selectedTab,
                navigationAnimation: tabAnimation
            )
            .padding(.horizontal, 4)
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
