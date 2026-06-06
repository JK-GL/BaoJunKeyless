import SwiftUI
import UIKit

// MARK: - Settings View (Tab 4 — XMusic SettingsPanelView style)
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var keylessSettings: KeylessSettingsStore

    @State private var showingResetAlert = false
    @State private var toastText: String?
    @State private var isPhotoPickerPresented = false
    @State private var isCrashLogExpanded = false
    @State private var crashLogText: String = ""
    @State private var exportedLogURL: URL?
    @State private var isShareSheetPresented = false

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
                    refreshCrashLog: refreshCrashLog,
                    copyRecentLog: copyRecentLog,
                    exportCrashLog: exportCrashLog
                )

                SettingsResetSection(
                    showingResetAlert: $showingResetAlert,
                    onReset: resetAllSettings
                )

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
        .sheet(isPresented: $isShareSheetPresented) {
            if let exportedLogURL {
                ShareSheet(activityItems: [exportedLogURL])
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
        let newText = CrashLogger.shared.readReversedRecentLog(limit: 300)
        if crashLogText != newText {
            crashLogText = newText
        }
    }

    private func copyRecentLog() {
        let text = CrashLogger.shared.readRecentLog(limit: 100)
        UIPasteboard.general.string = text.isEmpty ? crashLogText : text
        withAnimation { toastText = "已复制最近日志" }
    }

    private func exportCrashLog() {
        guard let url = CrashLogger.shared.exportLogFile(tag: "export") else {
            withAnimation { toastText = "暂无日志可导出" }
            return
        }
        exportedLogURL = url
        refreshCrashLog()
        isShareSheetPresented = true
    }

    private func resetAllSettings() {
        keylessSettings.reset()
        CustomVibrationStore.resetStoredPatterns()
        theme.resetAppearance()
        AppDiagnosticsSettings.resetHiddenDiagnosticsToggles()
        CrashLogger.shared.logCurrentStatus(tag: "reset")
        withAnimation { toastText = "设置已重置" }
    }
}
