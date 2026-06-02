import SwiftUI

// MARK: - Static Color Palette (fallback)
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
    case midnight, aurora, sunset, forest, custom
    static let storageKey = "BaoJun.SelectedTheme"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "极夜"; case .aurora: return "极光"
        case .sunset: return "日落"; case .forest: return "森屿"; case .custom: return "自定义"
        }
    }
    var subtitle: String {
        switch self {
        case .midnight: return "经典深色蓝紫氛围"; case .aurora: return "冷调蓝青霓虹"
        case .sunset: return "暖调红橙电影感"; case .forest: return "墨绿与金色层次"
        case .custom: return "自选背景图与按钮色"
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
        case .midnight: return [Color(red:0.07,green:0.07,blue:0.10), Color(red:0.04,green:0.04,blue:0.06), .black]
        case .aurora:   return [Color(red:0.03,green:0.08,blue:0.14), Color(red:0.02,green:0.05,blue:0.10), Color(red:0.01,green:0.02,blue:0.05)]
        case .sunset:   return [Color(red:0.16,green:0.06,blue:0.08), Color(red:0.10,green:0.04,blue:0.05), Color(red:0.04,green:0.02,blue:0.03)]
        case .forest:   return [Color(red:0.04,green:0.10,blue:0.08), Color(red:0.03,green:0.06,blue:0.05), Color(red:0.01,green:0.03,blue:0.02)]
        case .custom:   return [Color(red:0.06,green:0.07,blue:0.10), Color(red:0.03,green:0.04,blue:0.07), Color(red:0.01,green:0.01,blue:0.03)]
        }
    }
    fileprivate var presetPrimaryGlow: Color {
        switch self {
        case .midnight: return Color(red:0.99,green:0.28,blue:0.32).opacity(0.22)
        case .aurora:   return Color(red:0.33,green:0.92,blue:0.95).opacity(0.24)
        case .sunset:   return Color(red:1.00,green:0.42,blue:0.32).opacity(0.24)
        case .forest:   return Color(red:0.33,green:0.82,blue:0.53).opacity(0.22)
        case .custom:   return AppThemeDefaults.customAccent.opacity(0.28)
        }
    }
    fileprivate var presetSecondaryGlow: Color {
        switch self {
        case .midnight: return Color(red:0.23,green:0.66,blue:0.88).opacity(0.16)
        case .aurora:   return Color(red:0.44,green:0.52,blue:1.00).opacity(0.18)
        case .sunset:   return Color(red:1.00,green:0.80,blue:0.34).opacity(0.17)
        case .forest:   return Color(red:0.90,green:0.75,blue:0.36).opacity(0.16)
        case .custom:   return Color.white.opacity(0.16)
        }
    }
    static func resolve(from raw: String) -> AppThemePreset { AppThemePreset(rawValue: raw) ?? .midnight }
}

enum AppThemeDefaults { static let customAccent = Color(red: 0.72, green: 0.62, blue: 1.00) }

// MARK: - Theme Storage
enum AppThemeStorage {
    static let customAccentDataKey = "BaoJun.CustomThemeAccent"
    static let customBackgroundRevisionKey = "BaoJun.CustomThemeBGRevision"
    static let customBackgroundBlurKey = "BaoJun.CustomThemeBGBlur"
    private static let bgFile = "custom-theme-bg.jpg"

    static func customAccent(from data: Data) -> Color {
        guard !data.isEmpty, let p = try? JSONDecoder().decode(PersistedColor.self, from: data) else { return AppThemeDefaults.customAccent }
        return p.color
    }
    static func customAccentData(from color: Color) -> Data { (try? JSONEncoder().encode(PersistedColor(color))) ?? Data() }

    static func backgroundImageData() -> Data? {
        guard let u = backgroundImageURL(), FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try? Data(contentsOf: u)
    }
    static func saveBackgroundImageData(_ data: Data) throws {
        guard let u = backgroundImageURL() else { throw NSError(domain: "BaoJun.Theme", code: 1) }
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u, options: .atomic)
    }
    static func removeBackgroundImage() throws {
        guard let u = backgroundImageURL(), FileManager.default.fileExists(atPath: u.path) else { return }
        try FileManager.default.removeItem(at: u)
    }
    private static func backgroundImageURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("BaoJun", isDirectory: true).appendingPathComponent(bgFile)
    }
}

private struct PersistedColor: Codable {
    let r: Double, g: Double, b: Double, a: Double
    init(color: Color) {
        let ui = UIColor(color)
        var rr: CGFloat=1, gg: CGFloat=1, bb: CGFloat=1, aa: CGFloat=1
        ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r=Double(rr); g=Double(gg); b=Double(bb); a=Double(aa)
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
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
    var hasCustomBackgroundImage: Bool { !(customBackgroundImageData?.isEmpty ?? true) }

    init(selectedThemeRawValue: String, customAccentData: Data,
         customBackgroundRevision: Int, customBackgroundBlur: Double = 0) {
        preset = AppThemePreset.resolve(from: selectedThemeRawValue)
        customAccent = AppThemeStorage.customAccent(from: customAccentData)
        let bgData = customBackgroundRevision >= 0 ? AppThemeStorage.backgroundImageData() : nil
        customBackgroundImageData = preset == .custom ? bgData : nil
        self.customBackgroundBlur = CGFloat(min(max(customBackgroundBlur, 0), 36))
    }
}

// MARK: - Theme-Aware Dynamic Colors (reads UserDefaults)
struct ThemeColors {
    static var accent: Color { current.accent }
    static var cardBg: Color { Color.white.opacity(0.06) }
    static var cardStroke: Color { Color.white.opacity(0.08) }
    static var textPrimary: Color { .white }
    static var textSecondary: Color { Color.white.opacity(0.62) }
    static var textTertiary: Color { Color.white.opacity(0.45) }
    static var pillBg: Color { Color.white.opacity(0.10) }
    static var pillStroke: Color { Color.white.opacity(0.12) }
    static var tabBarBg: Color { .clear }

    private static var current: AppThemeConfiguration {
        let r = UserDefaults.standard.string(forKey: AppThemePreset.storageKey) ?? "midnight"
        let a = UserDefaults.standard.data(forKey: AppThemeStorage.customAccentDataKey) ?? Data()
        let rev = UserDefaults.standard.integer(forKey: AppThemeStorage.customBackgroundRevisionKey)
        let blur = UserDefaults.standard.double(forKey: AppThemeStorage.customBackgroundBlurKey)
        return AppThemeConfiguration(selectedThemeRawValue: r, customAccentData: a,
                                     customBackgroundRevision: rev, customBackgroundBlur: blur)
    }
}
