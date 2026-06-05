import Foundation

enum AppDiagnosticsSettings {
    static let diagnosticsEnabledKey = "Diagnostics.Enabled"
    static let disableBackgroundImageKey = "Diagnostics.DisableBackgroundImage"
    static let disableBackgroundBlurKey = "Diagnostics.DisableBackgroundBlur"
    static let disableThemePreviewKey = "Diagnostics.DisableThemePreview"
    static let disableRadarKey = "Diagnostics.DisableRadar"

    static var isDiagnosticsEnabled: Bool {
        UserDefaults.standard.object(forKey: diagnosticsEnabledKey) as? Bool ?? false
    }
}
