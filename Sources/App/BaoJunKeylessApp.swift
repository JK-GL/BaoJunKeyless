import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var keylessSettings = KeylessSettingsStore()
    @StateObject private var customVibrationStore = CustomVibrationStore()
    @StateObject private var vehicleEventLogStore = VehicleEventLogStore()
    @StateObject private var addressSettings = AddressServiceSettings()
    @StateObject private var vehicleCredentials = VehicleCredentialsStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var vehicleStore: VehicleStateStore = MQTTVehicleStateStore()

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
                .environmentObject(vehicleCredentials)
                .environmentObject(locationManager)
                .preferredColorScheme(.dark)
        }
    }
}
