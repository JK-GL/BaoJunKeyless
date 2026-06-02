import SwiftUI

// MARK: - App Color Theme (legacy constants)
struct AppTheme {
    static let accent  = Color.blue
    static let green   = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let red     = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let orange  = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let purple  = Color(red: 0.69, green: 0.32, blue: 0.87)
    static let cardBg  = Color(.systemBackground)
    static let pageBg  = Color(.systemGroupedBackground)
}

// MARK: - Theme Presets
enum AppThemePreset: String, CaseIterable, Identifiable {
    case midnight
    case aurora
    case sunset
    case forest
    case custom

    static let storageKey = "BaoJun.SelectedTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "极夜"
        case .aurora:   return "极光"
        case .sunset:   return "日落"
        case .forest:   return "森屿"
        case .custom:   return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .midnight: return "经典深色蓝紫氛围"
        case .aurora:   return "冷调蓝青霓虹"
        case .sunset:   return "暖调红橙电影感"
        case .forest:   return "墨绿与金色层次"
        case .custom:   return "自选背景图与按钮色"
        }
    }

    fileprivate var presetAccent: Color {
        switch self {
        case .midnight: return Color(red: 0.48, green: 0.92, blue: 0.72)
        case .aurora:   return Color(red: 0.41, green: 0.84, blue: 0.98)
        case .sunset:   return Color(red: 1.00, green: 0.62, blue: 0.37)
        case .forest:   return Color(red: 0.78, green: 0.91, blue: 0.50)
        case .custom:   return AppThemeDefaults.customAccent
        }
    }

    fileprivate var presetGradientColors: [Color] {
        switch self {
        case .midnight: return [Color(red: 0.07, green: 0.07, blue: 0.10),
                                Color(red: 0.04, green: 0.04, blue: 0.06), .black]
        case .aurora:   return [Color(red: 0.03, green: 0.08, blue: 0.14),
                                Color(red: 0.02, green: 0.05, blue: 0.10),
                                Color(red: 0.01, green: 0.02, blue: 0.05)]
        case .sunset:   return [Color(red: 0.16, green: 0.06, blue: 0.08),
                                Color(red: 0.10, green: 0.04, blue: 0.05),
                                Color(red: 0.04, green: 0.02, blue: 0.03)]
        case .forest:   return [Color(red: 0.04, green: 0.10, blue: 0.08),
                                Color(red: 0.03, green: 0.06, blue: 0.05),
                                Color(red: 0.01, green: 0.03, blue: 0.02)]
        case .custom:   return [Color(red: 0.06, green: 0.07, blue: 0.10),
                                Color(red: 0.03, green: 0.04, blue: 0.07),
                                Color(red: 0.01, green: 0.01, blue: 0.03)]
        }
    }

    fileprivate var presetPrimaryGlow: Color {
        switch self {
        case .midnight: return Color(red: 0.99, green: 0.28, blue: 0.32).opacity(0.22)
        case .aurora:   return Color(red: 0.33, green: 0.92, blue: 0.95).opacity(0.24)
        case .sunset:   return Color(red: 1.00, green: 0.42, blue: 0.32).opacity(0.24)
        case .forest:   return Color(red: 0.33, green: 0.82, blue: 0.53).opacity(0.22)
        case .custom:   return AppThemeDefaults.customAccent.opacity(0.28)
        }
    }

    fileprivate var presetSecondaryGlow: Color {
        switch self {
        case .midnight: return Color(red: 0.23, green: 0.66, blue: 0.88).opacity(0.16)
        case .aurora:   return Color(red: 0.44, green: 0.52, blue: 1.00).opacity(0.18)
        case .sunset:   return Color(red: 1.00, green: 0.80, blue: 0.34).opacity(0.17)
        case .forest:   return Color(red: 0.90, green: 0.75, blue: 0.36).opacity(0.16)
        case .custom:   return Color.white.opacity(0.16)
        }
    }

    static func resolve(from rawValue: String) -> AppThemePreset {
        AppThemePreset(rawValue: rawValue) ?? .midnight
    }
}

enum AppThemeDefaults {
    static let customAccent = Color(red: 0.72, green: 0.62, blue: 1.00)
}

// MARK: - Persisted Color
private struct PersistedThemeColor: Codable {
    let red: Double; let green: Double; let blue: Double; let alpha: Double

    @MainActor
    init(color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b); alpha = Double(a)
    }

    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

// MARK: - Theme Storage
enum AppThemeStorage {
    static let customAccentDataKey = "BaoJun.CustomThemeAccent"
    static let customBackgroundRevisionKey = "BaoJun.CustomThemeBGRevision"
    static let customBackgroundBlurKey = "BaoJun.CustomThemeBGBlur"
    private static let bgFileName = "custom-theme-bg.jpg"

    static func customAccent(from data: Data) -> Color {
        guard !data.isEmpty,
              let p = try? JSONDecoder().decode(PersistedThemeColor.self, from: data)
        else { return AppThemeDefaults.customAccent }
        return p.swiftUIColor
    }

    @MainActor
    static func customAccentData(from color: Color) -> Data {
        (try? JSONEncoder().encode(PersistedThemeColor(color: color))) ?? Data()
    }

    static func backgroundImageData() -> Data? {
        guard let url = backgroundImageURL(),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func saveBackgroundImageData(_ data: Data) throws {
        guard let url = backgroundImageURL() else {
            throw NSError(domain: "BaoJun.Theme", code: 1, userInfo: nil)
        }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func removeBackgroundImage() throws {
        guard let url = backgroundImageURL(),
              FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func backgroundImageURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("BaoJun", isDirectory: true)
            .appendingPathComponent(bgFileName)
    }
}

// MARK: - Theme Configuration
struct AppThemeConfiguration {
    let preset: AppThemePreset
    let customAccent: Color
    let customBackgroundImageData: Data?
    let customBackgroundBlur: CGFloat

    var accent: Color { preset == .custom ? customAccent : preset.presetAccent }
    var gradientColors: [Color] { preset.presetGradientColors }
    var primaryGlow: Color { preset == .custom ? customAccent.opacity(0.28) : preset.presetPrimaryGlow }
    var secondaryGlow: Color { preset.presetSecondaryGlow }

    init(selectedThemeRawValue: String, customAccentData: Data,
         customBackgroundRevision: Int, customBackgroundBlur: Double = 0) {
        preset = AppThemePreset.resolve(from: selectedThemeRawValue)
        customAccent = AppThemeStorage.customAccent(from: customAccentData)
        let bgData = customBackgroundRevision >= 0 ? AppThemeStorage.backgroundImageData() : nil
        customBackgroundImageData = preset == .custom ? bgData : nil
        self.customBackgroundBlur = CGFloat(min(max(customBackgroundBlur, 0), 36))
    }
}
