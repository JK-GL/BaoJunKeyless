import SwiftUI

struct ContentView: View {
    @StateObject private var theme = ThemeManager()
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: 0) {
                // Page content
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Custom tab bar
                CustomTabBar(selectedTab: $selectedTab, theme: theme)
            }
        }
        .environmentObject(theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: StatusView()
        case 1: KeylessView()
        case 2: LogView()
        case 3: SettingsView()
        default: StatusView()
        }
    }
}

// MARK: - Custom Tab Bar (XMusic style)
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @ObservedObject var theme: ThemeManager

    private let tabs: [(icon: String, label: String)] = [
        ("car.fill", "状态"),
        ("dot.radiowaves.left.and.right", "无感"),
        ("list.bullet.rectangle", "日志"),
        ("gearshape.fill", "设置")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button(action: { withAnimation(.spring(response: 0.3)) { selectedTab = i } }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: 20))
                            .symbolVariant(selectedTab == i ? .fill : .none)
                        Text(tabs[i].label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == i ? theme.accent : theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().background(theme.cardStroke)
        }
    }
}
