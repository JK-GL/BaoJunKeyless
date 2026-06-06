import SwiftUI

// MARK: - Settings View (Tab 4 — XMusic SettingsPanelView style)
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState

    @State private var showingResetAlert = false
    @State private var toastText: String?
    @State private var isPhotoPickerPresented = false
    @State private var isCrashLogExpanded = false
    @State private var crashLogText: String = ""

    private var currentTheme: AppThemeConfiguration {
        theme.current
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "设置")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                SettingsThemeSection(
                    currentTheme: currentTheme,
                    isPhotoPickerPresented: $isPhotoPickerPresented,
                    accentBinding: accentBinding,
                    backgroundBlurBinding: backgroundBlurBinding,
                    themeConfig: themeConfig
                )

                SettingsAboutSection()

                SettingsCrashLogSection(
                    crashLogText: $crashLogText,
                    isCrashLogExpanded: $isCrashLogExpanded,
                    toastText: $toastText,
                    refreshCrashLog: refreshCrashLog
                )

                SettingsResetSection(showingResetAlert: $showingResetAlert)

                Spacer(minLength: 100)
            }
        }
        .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
        .onDisappear {
            scrollState.reset()
        }
        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoPicker { data in
                if let data {
                    theme.saveCustomBackgroundImageData(data)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let text = toastText {
                ToastView(text: text)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { toastText = nil }
                        }
                    }
            }
        }
    }

    private var accentBinding: Binding<Color> {
        Binding(get: { currentTheme.customAccent },
                set: { theme.setCustomAccent($0) })
    }

    private var backgroundBlurBinding: Binding<Double> {
        Binding(get: { Double(currentTheme.customBackgroundBlur) },
                set: { theme.setBackgroundBlur($0) })
    }

    private func themeConfig(for preset: AppThemePreset) -> AppThemeConfiguration {
        theme.configuration(for: preset)
    }

    private func refreshCrashLog() {
        let newText = CrashLogger.shared.readReversedRecentLog(limit: 500)
        if crashLogText != newText {
            crashLogText = newText
        }
    }
}
