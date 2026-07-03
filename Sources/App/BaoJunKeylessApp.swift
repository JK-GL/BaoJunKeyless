import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var keylessSettings = KeylessSettingsStore.shared
    @StateObject private var customVibrationStore = CustomVibrationStore.shared
    @StateObject private var vehicleEventLogStore = VehicleEventLogStore.shared
    @StateObject private var addressSettings = AddressServiceSettings.shared
    @StateObject private var vehicleCredentials = VehicleCredentialsStore.shared
    @StateObject private var locationManager = LocationManager(addressSettings: AddressServiceSettings.shared)
    @StateObject private var vehicleStore: VehicleStateStore

    init() {
        _vehicleStore = StateObject(
            wrappedValue: MQTTVehicleStateStore(
                addressSettings: AddressServiceSettings.shared,
                credentialsStore: VehicleCredentialsStore.shared
            )
        )
        _ = CrashLogger.shared
        AppNotificationManager.shared.configure()
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
