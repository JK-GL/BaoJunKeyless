import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var keylessSettings = KeylessSettingsStore()
    @StateObject private var customVibrationStore = CustomVibrationStore()
    @StateObject private var vehicleEventLogStore = VehicleEventLogStore()
    @StateObject private var addressSettings = AddressServiceSettings()
    @StateObject private var vehicleStore: VehicleStateStore = MockVehicleStateStore()

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
                .environmentObject(customVibrationStore)
                .environmentObject(vehicleEventLogStore)
                .environmentObject(addressSettings)
                .environmentObject(vehicleStore)
                .preferredColorScheme(.dark)
        }
    }
}
