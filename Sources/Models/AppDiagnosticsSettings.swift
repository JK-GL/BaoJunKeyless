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
}
