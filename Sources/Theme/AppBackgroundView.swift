import SwiftUI

struct AppBackgroundView: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Custom background image
                if let img = customImage {
                    img.resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: theme.config.customBackgroundBlur).clipped()
                    LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.48), .black.opacity(0.68)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }

                // Gradient base
                LinearGradient(colors: theme.config.gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(theme.config.hasCustomBackgroundImage ? 0.56 : 1)

                // Primary glow
                Circle().fill(theme.config.primaryGlow)
                    .frame(width: 320, height: 320).blur(radius: 80)
                    .offset(x: -120, y: -260)

                // Secondary glow
                Circle().fill(theme.config.secondaryGlow)
                    .frame(width: 300, height: 300).blur(radius: 86)
                    .offset(x: 140, y: 120)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var customImage: Image? {
        guard let data = theme.config.customBackgroundImageData,
              let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
    }
}
