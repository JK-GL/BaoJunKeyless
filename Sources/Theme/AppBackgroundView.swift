import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 应用全局背景层，提供统一的渐变和光斑氛围。
struct AppBackgroundView: View {
    @AppStorage(AppThemePreset.storageKey) private var selectedThemeRawValue = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) private var customAccentData = Data()
    @AppStorage(AppThemeStorage.customBackgroundRevisionKey) private var customBackgroundRevision = 0
    @AppStorage(AppThemeStorage.customBackgroundBlurKey) private var customBackgroundBlur = 0.0

    @State private var cachedSelectedThemeRawValue: String = ""
    @State private var cachedBackgroundRevision: Int = .min
    @State private var cachedBackgroundImage: Image?
    @State private var cachedBlur: CGFloat = 0

    private var theme: AppThemeConfiguration {
        AppThemeConfiguration(
            selectedThemeRawValue: selectedThemeRawValue,
            customAccentData: customAccentData,
            customBackgroundRevision: customBackgroundRevision,
            customBackgroundBlur: customBackgroundBlur
        )
    }

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
                        .blur(radius: cachedBlur)
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
                    colors: theme.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(backgroundImage == nil ? 1 : 0.56)

                Circle()
                    .fill(theme.primaryGlow)
                    .frame(width: 320, height: 320)
                    .blur(radius: 80)
                    .offset(x: -120, y: -260)

                Circle()
                    .fill(theme.secondaryGlow)
                    .frame(width: 300, height: 300)
                    .blur(radius: 86)
                    .offset(x: 140, y: 120)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear { updateCache() }
        .onChange(of: selectedThemeRawValue) { _ in updateCache() }
        .onChange(of: customAccentData) { _ in updateCache() }
        .onChange(of: customBackgroundRevision) { _ in updateCache() }
        .onChange(of: customBackgroundBlur) { _ in updateCache() }
    }

    private func updateCache() {
        if cachedSelectedThemeRawValue == selectedThemeRawValue && cachedBackgroundRevision == customBackgroundRevision { return }
        cachedSelectedThemeRawValue = selectedThemeRawValue
        cachedBackgroundRevision = customBackgroundRevision
        cachedBlur = customBackgroundBlur
        #if canImport(UIKit)
        let currentTheme = theme
        if currentTheme.preset == .custom, let uiImage = AppThemeStorage.cachedUIImage(for: customBackgroundRevision) {
            cachedBackgroundImage = Image(uiImage: uiImage)
        } else {
            cachedBackgroundImage = nil
        }
        #endif
    }

    private var backgroundImage: Image? { cachedBackgroundImage }
}
