import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 应用全局背景层，提供统一的渐变和光斑氛围。
struct AppBackgroundView: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let backgroundImage {
                    backgroundImage
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: theme.current.customBackgroundBlur)
                        .clipped()

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.34),
                            Color.black.opacity(0.48),
                            Color.black.opacity(0.68)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: theme.current.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(backgroundImage == nil ? 1 : 0.56)

                Circle()
                    .fill(theme.current.primaryGlow)
                    .frame(width: 320, height: 320)
                    .blur(radius: 80)
                    .offset(x: -120, y: -260)

                Circle()
                    .fill(theme.current.secondaryGlow)
                    .frame(width: 300, height: 300)
                    .blur(radius: 86)
                    .offset(x: 140, y: 120)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { theme.refreshBackgroundImageIfNeeded() }
        .onChange(of: theme.selectedThemeRawValue) { _ in theme.refreshBackgroundImageIfNeeded() }
        .onChange(of: theme.customBackgroundRevision) { _ in theme.refreshBackgroundImageIfNeeded() }
        .onChange(of: theme.customBackgroundBlur) { _ in theme.refreshBackgroundImageIfNeeded() }
    }

    #if canImport(UIKit)
    private var backgroundImage: Image? {
        guard theme.selectedThemeRawValue == "custom",
              let uiImage = theme.cachedBackgroundUIImage
        else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
    #else
    private var backgroundImage: Image? { nil }
    #endif
}
