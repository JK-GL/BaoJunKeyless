import SwiftUI

struct AppBackgroundView: View {
    @AppStorage(AppThemePreset.storageKey) private var themeRaw = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) private var accentData = Data()
    @AppStorage(AppThemeStorage.customBackgroundRevisionKey) private var bgRevision = 0
    @AppStorage(AppThemeStorage.customBackgroundBlurKey) private var bgBlur = 0.0

    private var theme: AppThemeConfiguration {
        AppThemeConfiguration(selectedThemeRawValue: themeRaw, customAccentData: accentData,
                              customBackgroundRevision: bgRevision, customBackgroundBlur: bgBlur)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Custom background image
                if let img = customImage {
                    img.resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: theme.customBackgroundBlur).clipped()
                    LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.48), .black.opacity(0.68)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }

                // Gradient base
                LinearGradient(colors: theme.gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(customImage == nil ? 1 : 0.56)

                // Primary glow
                Circle().fill(theme.primaryGlow)
                    .frame(width: 320, height: 320).blur(radius: 80)
                    .offset(x: -120, y: -260)

                // Secondary glow
                Circle().fill(theme.secondaryGlow)
                    .frame(width: 300, height: 300).blur(radius: 86)
                    .offset(x: 140, y: 120)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var customImage: Image? {
        guard let data = theme.customBackgroundImageData,
              let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
    }
}
