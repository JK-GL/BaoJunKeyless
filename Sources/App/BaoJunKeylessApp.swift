import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var keylessSettings = KeylessSettingsStore.shared
    @StateObject private var customVibrationStore = CustomVibrationStore.shared
    @StateObject private var vehicleEventLogStore = VehicleEventLogStore.shared
    @StateObject private var addressSettings = AddressServiceSettings.shared
    @StateObject private var vehicleCredentials = VehicleCredentialsStore.shared
    @StateObject private var locationManager: LocationManager
    @StateObject private var vehicleStore: VehicleStateStore

    init() {
        let location = LocationManager(addressSettings: AddressServiceSettings.shared)
        _locationManager = StateObject(wrappedValue: location)
        // 供状态页子树按引用取用，避免 @EnvironmentObject 订阅高频 distance 导致整页重绘。
        LocationManagerBridge.current = location
        _vehicleStore = StateObject(
            wrappedValue: MQTTVehicleStateStore(
                addressSettings: AddressServiceSettings.shared,
                credentialsStore: VehicleCredentialsStore.shared
            )
        )
        _ = CrashLogger.shared
        AppNotificationManager.shared.configure()
        // 启动后台增强运行时（围栏 / 保活 / background task）
        _ = BackgroundExecutionManager.shared
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
