import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - App Theme Color Constants
struct AppTheme {
    static let accent  = Color.blue
    static let green   = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let red     = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let orange  = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let purple  = Color(red: 0.69, green: 0.32, blue: 0.87)
    static let cardBg  = Color.white.opacity(0.06)
    static let pageBg  = Color.clear
}

// MARK: - Theme Manager (single source of truth for theme state)
@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var selectedThemeRawValue: String
    @Published private(set) var customAccentData: Data
    @Published private(set) var customBackgroundRevision: Int
    @Published private(set) var customBackgroundBlur: Double

    #if canImport(UIKit)
    @Published private(set) var storedBackgroundImage: UIImage?
    #endif

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedThemeRawValue = defaults.string(forKey: AppThemePreset.storageKey) ?? AppThemePreset.midnight.rawValue
        customAccentData = defaults.data(forKey: AppThemeStorage.customAccentDataKey) ?? Data()
        customBackgroundRevision = defaults.object(forKey: AppThemeStorage.customBackgroundRevisionKey) as? Int ?? 0
        customBackgroundBlur = defaults.object(forKey: AppThemeStorage.customBackgroundBlurKey) as? Double ?? 0
        #if canImport(UIKit)
        storedBackgroundImage = nil
        #endif
        refreshBackgroundImage()
    }

    var current: AppThemeConfiguration {
        AppThemeConfiguration(
            selectedThemeRawValue: selectedThemeRawValue,
            customAccentData: customAccentData,
            customBackgroundRevision: customBackgroundRevision,
            customBackgroundBlur: customBackgroundBlur
        )
    }

    var accent: Color { current.accent }

    #if canImport(UIKit)
    var currentBackgroundImage: UIImage? {
        guard !DeviceMemoryProfile.shouldUseLightweightImages else { return nil }
        return current.preset == .custom ? storedBackgroundImage : nil
    }

    var customThemePreviewImage: UIImage? {
        guard !DeviceMemoryProfile.shouldUseLightweightImages else { return nil }
        return storedBackgroundImage
    }
    #endif

    func configuration(for preset: AppThemePreset) -> AppThemeConfiguration {
        AppThemeConfiguration(
            selectedThemeRawValue: preset.rawValue,
            customAccentData: preset == .custom ? customAccentData : Data(),
            customBackgroundRevision: customBackgroundRevision,
            customBackgroundBlur: customBackgroundBlur
        )
    }

    func setThemePreset(_ preset: AppThemePreset) {
        selectedThemeRawValue = preset.rawValue
        defaults.set(preset.rawValue, forKey: AppThemePreset.storageKey)
    }

    func setCustomAccent(_ color: Color) {
        let data = AppThemeStorage.customAccentData(from: color)
        customAccentData = data
        defaults.set(data, forKey: AppThemeStorage.customAccentDataKey)
    }

    func setBackgroundBlur(_ blur: Double) {
        let clamped = min(max(blur, 0), 36)
        customBackgroundBlur = clamped
        defaults.set(clamped, forKey: AppThemeStorage.customBackgroundBlurKey)
    }

    func saveCustomBackgroundImageData(_ data: Data) {
        try? AppThemeStorage.saveBackgroundImageData(data)
        if AppDiagnosticsSettings.isDiagnosticsEnabled,
           let image = UIImage(data: data) {
            CrashLogger.shared.logImageDiagnostics(
                "ThemeSave",
                width: image.size.width,
                height: image.size.height,
                bytes: data.count,
                note: "save"
            )
        }
        if selectedThemeRawValue != AppThemePreset.custom.rawValue {
            selectedThemeRawValue = AppThemePreset.custom.rawValue
            defaults.set(selectedThemeRawValue, forKey: AppThemePreset.storageKey)
        }
        customBackgroundRevision += 1
        defaults.set(customBackgroundRevision, forKey: AppThemeStorage.customBackgroundRevisionKey)
        refreshBackgroundImage()
    }

    func removeCustomBackgroundImage() {
        try? AppThemeStorage.removeBackgroundImage()
        customBackgroundRevision += 1
        defaults.set(customBackgroundRevision, forKey: AppThemeStorage.customBackgroundRevisionKey)
        refreshBackgroundImage()
    }

    // MARK: - XMusic Color Tokens (always dark, white-based)

    var cardBg: Color {
        Color.white.opacity(0.06)
    }

    var cardStroke: Color {
        Color.white.opacity(0.08)
    }

    var textPrimary: Color {
        .white
    }

    var textSecondary: Color {
        Color.white.opacity(0.62)
    }

    var textTertiary: Color {
        Color.white.opacity(0.45)
    }

    var pillBg: Color {
        Color.white.opacity(0.10)
    }

    var pillStroke: Color {
        Color.white.opacity(0.12)
    }

    private func refreshBackgroundImage() {
        #if canImport(UIKit)
        guard !DeviceMemoryProfile.shouldUseLightweightImages else {
            storedBackgroundImage = nil
            AppThemeStorage.invalidateBackgroundImageCache()
            return
        }
        storedBackgroundImage = AppThemeStorage.hasBackgroundImage()
            ? AppThemeStorage.cachedUIImage(for: customBackgroundRevision)
            : nil
        #endif
    }
}
