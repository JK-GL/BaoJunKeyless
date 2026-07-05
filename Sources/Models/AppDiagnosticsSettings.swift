import Foundation

enum AppDiagnosticsSettings {
    static let diagnosticsEnabledKey = "Diagnostics.Enabled"
    static let disableBackgroundImageKey = "Diagnostics.DisableBackgroundImage"
    static let disableBackgroundBlurKey = "Diagnostics.DisableBackgroundBlur"
    static let disableThemePreviewKey = "Diagnostics.DisableThemePreview"
    static let disableRadarKey = "Diagnostics.DisableRadar"
    static let useSFRadarCarIconKey = "Diagnostics.UseSFRadarCarIcon"
    static let enableRadarScanKey = "Diagnostics.EnableRadarScan"
    static let enableRadarGradientKey = "Diagnostics.EnableRadarGradient"
    static let vehicleControlRouteModeKey = "Diagnostics.VehicleControlRouteMode"

    static var isDiagnosticsEnabled: Bool {
        UserDefaults.standard.object(forKey: diagnosticsEnabledKey) as? Bool ?? false
    }

    static var isRadarScanEnabled: Bool {
        UserDefaults.standard.object(forKey: enableRadarScanKey) as? Bool ?? false
    }

    static var shouldUseSFRadarCarIcon: Bool {
        UserDefaults.standard.object(forKey: useSFRadarCarIconKey) as? Bool ?? false
    }

    static var isRadarGradientEnabled: Bool {
        UserDefaults.standard.object(forKey: enableRadarGradientKey) as? Bool ?? false
    }

    static var vehicleControlRouteMode: VehicleControlRouteMode {
        let raw = UserDefaults.standard.string(forKey: vehicleControlRouteModeKey) ?? VehicleControlRouteMode.auto.rawValue
        return VehicleControlRouteMode(rawValue: raw) ?? .auto
    }

    static func resetHiddenDiagnosticsToggles() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: diagnosticsEnabledKey)
        defaults.set(false, forKey: disableBackgroundImageKey)
        defaults.set(false, forKey: disableBackgroundBlurKey)
        defaults.set(false, forKey: disableThemePreviewKey)
        defaults.set(false, forKey: disableRadarKey)
        defaults.set(false, forKey: useSFRadarCarIconKey)
        defaults.set(false, forKey: enableRadarScanKey)
        defaults.set(false, forKey: enableRadarGradientKey)
        defaults.set(VehicleControlRouteMode.auto.rawValue, forKey: vehicleControlRouteModeKey)
    }
}
