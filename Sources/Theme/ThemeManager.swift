import SwiftUI
import Combine

// MARK: - Theme Manager (bridges AppThemeConfiguration to EnvironmentObject)
class ThemeManager: ObservableObject {
    @AppStorage(AppThemePreset.storageKey) var selectedThemeRawValue = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) var customAccentData = Data()
    @AppStorage(AppThemeStorage.customBackgroundRevisionKey) var customBackgroundRevision = 0
    @AppStorage(AppThemeStorage.customBackgroundBlurKey) var customBackgroundBlur: Double = 0
    @AppStorage("isDarkMode") var isDark = true

    init() {}

    var current: AppThemeConfiguration {
        AppThemeConfiguration(
            selectedThemeRawValue: selectedThemeRawValue,
            customAccentData: customAccentData,
            customBackgroundRevision: customBackgroundRevision,
            customBackgroundBlur: customBackgroundBlur
        )
    }

    // Dynamic colors for views
    var accent: Color { current.accent }

    var cardBg: Color {
        Color.white.opacity(isDark ? 0.06 : 0.04)
    }

    var cardStroke: Color {
        Color.white.opacity(isDark ? 0.08 : 0.06)
    }

    var textPrimary: Color {
        isDark ? .white : .black
    }

    var textSecondary: Color {
        isDark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
    }

    var textTertiary: Color {
        isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.4)
    }

    var pillBg: Color {
        Color.white.opacity(isDark ? 0.10 : 0.06)
    }

    var pillStroke: Color {
        Color.white.opacity(isDark ? 0.12 : 0.08)
    }
}
