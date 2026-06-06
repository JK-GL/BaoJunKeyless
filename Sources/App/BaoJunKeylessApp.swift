import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var keylessSettings = KeylessSettingsStore()

    init() {
        _ = CrashLogger.shared
        AppDiagnosticsSettings.resetHiddenDiagnosticsToggles()
        if CrashLogger.shared.isLoggingEnabled {
            CrashLogger.shared.logMemoryBaseline()
            CrashLogger.shared.startMemoryMonitor()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .environmentObject(keylessSettings)
                .preferredColorScheme(.dark)
        }
    }
}
