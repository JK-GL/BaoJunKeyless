import SwiftUI

struct ContentView: View {
    @StateObject private var theme = ThemeManager()
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            AppBackgroundView()
                .environmentObject(theme)

            TabView(selection: $selectedTab) {
                StatusView()
                    .tabItem { Label("状态", systemImage: "car.fill") }
                    .tag(0)

                KeylessView()
                    .tabItem { Label("无感", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(1)

                LogView()
                    .tabItem { Label("日志", systemImage: "list.bullet.rectangle") }
                    .tag(2)

                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
                    .tag(3)
            }
            .tint(theme.accent)
        }
        .environmentObject(theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}
