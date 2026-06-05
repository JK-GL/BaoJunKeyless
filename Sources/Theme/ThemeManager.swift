import SwiftUI

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

// MARK: - Theme Manager (bridges AppThemeConfiguration to EnvironmentObject)
class ThemeManager: ObservableObject {
    @AppStorage(AppThemePreset.storageKey) var selectedThemeRawValue = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) var customAccentData = Data()
    @AppStorage(AppThemeStorage.customBackgroundRevisionKey) var customBackgroundRevision = 0
    @AppStorage(AppThemeStorage.customBackgroundBlurKey) var customBackgroundBlur: Double = 0

    // 缓存的背景 UIImage，跨 tab 持久
    private(set) var cachedBackgroundUIImage: UIImage?
    private var cachedBackgroundRevision: Int = .min

    init() {}

    func refreshBackgroundImageIfNeeded() {
        let rev = customBackgroundRevision
        if cachedBackgroundRevision == rev { return }
        cachedBackgroundRevision = rev
        cachedBackgroundUIImage = AppThemeStorage.cachedUIImage(for: rev)
    }

    var current: AppThemeConfiguration {
        AppThemeConfiguration(
            selectedThemeRawValue: selectedThemeRawValue,
            customAccentData: customAccentData,
            customBackgroundRevision: customBackgroundRevision,
            customBackgroundBlur: customBackgroundBlur
        )
    }

    // Dynamic accent from theme system
    var accent: Color { current.accent }

    // MARK: - XMusic Color Tokens (always dark, white-based)
    // Matches XMusic's direct Color.white.opacity() usage

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
}
