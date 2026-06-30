import SwiftUI

struct SettingsThemeSection: View {
    @EnvironmentObject var theme: ThemeManager
    let currentTheme: AppThemeConfiguration
    @Binding var isPhotoPickerPresented: Bool
    let accentBinding: Binding<Color>
    let backgroundBlurBinding: Binding<Double>
    let themeConfig: (AppThemePreset) -> AppThemeConfiguration

    var body: some View {
        SettingsPanelView(title: "外观与皮肤", subtitle: "切换主题或设置自定义背景。") {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(AppThemePreset.allCases) { preset in
                            Button {
                                theme.setThemePreset(preset)
                            } label: {
                                ThemeOptionCardView(
                                    theme: themeConfig(preset),
                                    isSelected: currentTheme.preset == preset,
                                    previewUIImage: preset == .custom ? theme.customThemePreviewImage : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }

                if currentTheme.preset == .custom {
                    SettingsCustomThemeEditor(
                        currentTheme: currentTheme,
                        isPhotoPickerPresented: $isPhotoPickerPresented,
                        accentBinding: accentBinding,
                        backgroundBlurBinding: backgroundBlurBinding
                    )
                }
            }
        }
    }
}

private struct SettingsCustomThemeEditor: View {
    @EnvironmentObject var theme: ThemeManager
    let currentTheme: AppThemeConfiguration
    @Binding var isPhotoPickerPresented: Bool
    let accentBinding: Binding<Color>
    let backgroundBlurBinding: Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("主色调")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                ColorPicker("", selection: accentBinding)
                    .labelsHidden()
            }

            HStack {
                Text("背景图")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer()
                Button(currentTheme.hasCustomBackgroundImage ? "更换" : "选择图片") {
                    isPhotoPickerPresented = true
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(currentTheme.accent)
            }

            if currentTheme.hasCustomBackgroundImage {
                HStack {
                    Text("模糊度")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))
                    Spacer()
                    Slider(value: backgroundBlurBinding, in: 0...36)
                        .frame(width: 160)
                        .tint(currentTheme.accent)
                    Text("\(Int(currentTheme.customBackgroundBlur))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.62))
                }

                Button("移除背景图") {
                    theme.removeCustomBackgroundImage()
                }
                .font(.caption)
                .foregroundStyle(Color.red.opacity(0.8))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
