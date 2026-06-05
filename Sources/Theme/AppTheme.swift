import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppThemePreset: String, CaseIterable, Identifiable {
    case midnight
    case aurora
    case sunset
    case forest
    case custom

    static let storageKey = "XMusic.SelectedTheme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: return "极夜"
        case .aurora: return "极光"
        case .sunset: return "日落"
        case .forest: return "森屿"
        case .custom: return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .midnight: return "经典深色蓝紫氛围"
        case .aurora: return "冷调蓝青霓虹"
        case .sunset: return "暖调红橙电影感"
        case .forest: return "墨绿与金色层次"
        case .custom: return "自选背景图与按钮色"
        }
    }

    fileprivate var presetAccent: Color {
        switch self {
        case .midnight: return Color(red: 0.48, green: 0.92, blue: 0.72)
        case .aurora: return Color(red: 0.41, green: 0.84, blue: 0.98)
        case .sunset: return Color(red: 1.00, green: 0.62, blue: 0.37)
        case .forest: return Color(red: 0.78, green: 0.91, blue: 0.50)
        case .custom: return AppThemeDefaults.customAccent
        }
    }

    fileprivate var presetGradientColors: [Color] {
        switch self {
        case .midnight:
            return [Color(red: 0.07, green: 0.07, blue: 0.10), Color(red: 0.04, green: 0.04, blue: 0.06), .black]
        case .aurora:
            return [Color(red: 0.03, green: 0.08, blue: 0.14), Color(red: 0.02, green: 0.05, blue: 0.10), Color(red: 0.01, green: 0.02, blue: 0.05)]
        case .sunset:
            return [Color(red: 0.16, green: 0.06, blue: 0.08), Color(red: 0.10, green: 0.04, blue: 0.05), Color(red: 0.04, green: 0.02, blue: 0.03)]
        case .forest:
            return [Color(red: 0.04, green: 0.10, blue: 0.08), Color(red: 0.03, green: 0.06, blue: 0.05), Color(red: 0.01, green: 0.03, blue: 0.02)]
        case .custom:
            return [Color(red: 0.06, green: 0.07, blue: 0.10), Color(red: 0.03, green: 0.04, blue: 0.07), Color(red: 0.01, green: 0.01, blue: 0.03)]
        }
    }

    fileprivate var presetPrimaryGlow: Color {
        switch self {
        case .midnight: return Color(red: 0.99, green: 0.28, blue: 0.32).opacity(0.22)
        case .aurora: return Color(red: 0.33, green: 0.92, blue: 0.95).opacity(0.24)
        case .sunset: return Color(red: 1.00, green: 0.42, blue: 0.32).opacity(0.24)
        case .forest: return Color(red: 0.33, green: 0.82, blue: 0.53).opacity(0.22)
        case .custom: return AppThemeDefaults.customAccent.opacity(0.28)
        }
    }

    fileprivate var presetSecondaryGlow: Color {
        switch self {
        case .midnight: return Color(red: 0.23, green: 0.66, blue: 0.88).opacity(0.16)
        case .aurora: return Color(red: 0.44, green: 0.52, blue: 1.00).opacity(0.18)
        case .sunset: return Color(red: 1.00, green: 0.80, blue: 0.34).opacity(0.17)
        case .forest: return Color(red: 0.90, green: 0.75, blue: 0.36).opacity(0.16)
        case .custom: return Color.white.opacity(0.16)
        }
    }

    static func resolve(from rawValue: String) -> AppThemePreset { AppThemePreset(rawValue: rawValue) ?? .midnight }
}

enum AppThemeDefaults { static let customAccent = Color(red: 0.72, green: 0.62, blue: 1.00) }

private struct PersistedThemeColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    @MainActor
    init(color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b); alpha = Double(a)
        #elseif canImport(AppKit)
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        red = Double(nsColor.redComponent); green = Double(nsColor.greenComponent); blue = Double(nsColor.blueComponent); alpha = Double(nsColor.alphaComponent)
        #else
        red = 1; green = 1; blue = 1; alpha = 1
        #endif
    }

    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

enum AppThemeStorage {
    static let customAccentDataKey = "XMusic.CustomThemeAccent"
    static let customBackgroundRevisionKey = "XMusic.CustomThemeBackgroundRevision"
    static let customBackgroundBlurKey = "XMusic.CustomThemeBackgroundBlur"
    private static let backgroundFileName = "custom-theme-background.jpg"

    private static var cachedBackgroundData: Data?
    private static var cachedBackgroundRevision: Int = .min
    private static var cachedBackgroundUIImage: UIImage?

    static func customAccent(from data: Data) -> Color {
        guard !data.isEmpty, let persisted = try? JSONDecoder().decode(PersistedThemeColor.self, from: data) else {
            return AppThemeDefaults.customAccent
        }
        return persisted.swiftUIColor
    }

    @MainActor
    static func customAccentData(from color: Color) -> Data {
        (try? JSONEncoder().encode(PersistedThemeColor(color: color))) ?? Data()
    }

    static func backgroundImageData(revision: Int) -> Data? {
        if cachedBackgroundRevision == revision, let cachedBackgroundData { return cachedBackgroundData }
        guard let url = backgroundImageURL(), FileManager.default.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
            cachedBackgroundData = nil
            cachedBackgroundRevision = revision
            return nil
        }
        cachedBackgroundData = data
        cachedBackgroundRevision = revision
        return data
    }

    static func cachedUIImage(for revision: Int) -> UIImage? {
        if cachedBackgroundRevision == revision, let cachedBackgroundUIImage { return cachedBackgroundUIImage }
        guard let data = backgroundImageData(revision: revision) else {
            cachedBackgroundUIImage = nil
            return nil
        }
        cachedBackgroundUIImage = UIImage(data: data)
        return cachedBackgroundUIImage
    }

    static func invalidateBackgroundImageCache() {
        cachedBackgroundUIImage = nil
    }

    static func saveBackgroundImageData(_ data: Data) throws {
        guard let url = backgroundImageURL() else {
            throw NSError(domain: "XMusic.AppTheme", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法定位主题背景存储目录。"])
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: url, options: .atomic)
        cachedBackgroundData = data
        cachedBackgroundRevision = (cachedBackgroundRevision == .min ? 0 : cachedBackgroundRevision + 1)
    }

    static func removeBackgroundImage() throws {
        guard let url = backgroundImageURL(), FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        cachedBackgroundData = nil
        cachedBackgroundRevision = .min
    }

    private static func backgroundImageURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("XMusic", isDirectory: true)
            .appendingPathComponent(backgroundFileName)
    }
}

struct AppThemeConfiguration {
    let preset: AppThemePreset
    let customAccent: Color
    let customBackgroundImageData: Data?
    let customBackgroundRevision: Int
    let customBackgroundBlur: CGFloat

    var accent: Color { preset == .custom ? customAccent : preset.presetAccent }
    var gradientColors: [Color] { preset.presetGradientColors }
    var primaryGlow: Color { preset == .custom ? customAccent.opacity(0.28) : preset.presetPrimaryGlow }
    var secondaryGlow: Color { preset.presetSecondaryGlow }
    var hasCustomBackgroundImage: Bool { !(customBackgroundImageData?.isEmpty ?? true) }

    init(selectedThemeRawValue: String, customAccentData: Data, customBackgroundRevision: Int, customBackgroundBlur: Double = 0) {
        preset = AppThemePreset.resolve(from: selectedThemeRawValue)
        customAccent = AppThemeStorage.customAccent(from: customAccentData)
        let storedBackgroundData = customBackgroundRevision >= 0 ? AppThemeStorage.backgroundImageData(revision: customBackgroundRevision) : nil
        customBackgroundImageData = preset == .custom ? storedBackgroundData : nil
        self.customBackgroundRevision = customBackgroundRevision
        self.customBackgroundBlur = CGFloat(min(max(customBackgroundBlur, 0), 36))
    }
}
