import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
    }
}
