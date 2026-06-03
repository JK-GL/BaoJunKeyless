import SwiftUI

struct ContentView: View {
    private static let tabSwitchAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)

    @State private var selectedTab: AppTab = .status
    @Namespace private var tabAnimation

    var body: some View {
        ZStack {
            AppBackgroundView()

            tabContent(for: selectedTab)
                .id(selectedTab)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                PageHeaderView(
                    title: tabTitle(for: tab),
                    showsSettingsButton: tab == .status
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                tabBody(for: tab)
                    .padding(.top, 12)

                Spacer(minLength: 100)
            }
        }
    }

    private func tabTitle(for tab: AppTab) -> String {
        switch tab {
        case .status:   return "宝骏云海"
        case .keyless:  return "无感车控"
        case .logs:     return "日志"
        case .settings: return "设置"
        }
    }

    @ViewBuilder
    private func tabBody(for tab: AppTab) -> some View {
        switch tab {
        case .status:   StatusView()
        case .keyless:  KeylessView()
        case .logs:     LogView()
        case .settings: SettingsView()
        }
    }
}
