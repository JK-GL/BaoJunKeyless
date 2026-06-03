import SwiftUI

struct ContentView: View {
    @StateObject private var theme = ThemeManager()
    @State private var selectedTab = 0
    @Namespace private var tabAnimation

    var body: some View {
        ZStack {
            AppBackgroundView()

            VStack(spacing: 0) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: selectedTab)

                CustomTabBar(selectedTab: $selectedTab, theme: theme, tabAnimation: tabAnimation)
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

// MARK: - Custom Tab Bar (XMusic style with matchedGeometry)
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @ObservedObject var theme: ThemeManager
    var tabAnimation: Namespace.ID

    private let tabs: [(icon: String, label: String)] = [
        ("car.fill", "状态"),
        ("dot.radiowaves.left.and.right", "无感"),
        ("list.bullet.rectangle", "日志"),
        ("gearshape.fill", "设置")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<tabs.count, id: \.self) { i in
                Button(action: {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { selectedTab = i }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: selectedTab == i ? 20 : 18,
                                          weight: .semibold))
                            .symbolVariant(selectedTab == i ? .fill : .none)

                        Text(tabs[i].label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selectedTab == i ? theme.accent : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        if selectedTab == i {
                            selectedBackground
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(tabBarBackground)
        .contentShape(Capsule())
        .onTapGesture {}
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Selected tab background (matched geometry)
    private var selectedBackground: some View {
        Capsule()
            .fill(theme.accent.opacity(0.15))
            .overlay(Capsule().fill(LinearGradient(
                colors: [Color.white.opacity(0.2), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
            .matchedGeometryEffect(id: "tab-selection", in: tabAnimation)
    }

    // MARK: - Tab bar background (4 layers like XMusic)
    private var tabBarBackground: some View {
        Capsule()
            .fill(.regularMaterial)
            .overlay(Capsule().fill(LinearGradient(
                colors: [Color.white.opacity(0.15), .clear, Color.white.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Capsule().stroke(LinearGradient(
                colors: [Color.white.opacity(0.35), .clear, Color.white.opacity(0.15)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5))
            .overlay(Capsule().fill(Color.primary).opacity(0.02))
    }


}
