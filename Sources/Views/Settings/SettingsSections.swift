import SwiftUI
import Combine

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

struct SettingsAboutSection: View {
    var body: some View {
        SettingsPanelView(title: "关于") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsStatusRowView(title: "插件版本", value: "v1.0.0")
                SettingsStatusRowView(title: "构建号", value: "2026.05.31")
                SettingsStatusRowView(title: "框架", value: "Theos / Logos")
                SettingsStatusRowView(title: "越狱", value: "Dopamine rootless")
            }
        }
    }
}

struct SettingsResetSection: View {
    @Binding var showingResetAlert: Bool

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { showingResetAlert = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                    Text("重置全部设置")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
            .darkAlert(
                isPresented: $showingResetAlert,
                title: "重置插件",
                message: "确定要重置全部插件数据吗？此操作不可撤销。",
                confirmTitle: "确认重置",
                confirmColor: .red
            ) { }
        }
        .padding(.horizontal, 16)
    }
}

struct SettingsCrashLogSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var crashLogText: String
    @Binding var isCrashLogExpanded: Bool
    @Binding var toastText: String?
    let crashLogTimer: Timer.TimerPublisher
    @Binding var crashLogTimerCancellable: Cancellable?
    let refreshCrashLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28)) { isCrashLogExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(Color.red.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold))
                    Text("崩溃日志")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isCrashLogExpanded ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCrashLogExpanded {
                Divider().background(theme.cardStroke)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if crashLogText.isEmpty {
                            Text("暂无记录")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.45))
                        } else {
                            Text("有记录")
                                .font(.caption2)
                                .foregroundStyle(Color.orange.opacity(0.9))
                        }

                        Spacer()

                        Text("记录开关")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.45))

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { CrashLogger.shared.isLoggingEnabled },
                                set: { CrashLogger.shared.setLoggingEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(theme.accent)
                        .scaleEffect(0.7)
                    }

                    if crashLogText.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.green)
                                .font(.system(size: 14))
                            Text("暂无崩溃记录")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(crashLogText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.62))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = crashLogText
                            withAnimation { toastText = "已复制到剪贴板" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                Text("复制")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            CrashLogger.shared.clearLog()
                            refreshCrashLog()
                            withAnimation { toastText = "日志已清空" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("清空")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(Color.red.opacity(0.8))
                        }
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .onAppear {
            if isCrashLogExpanded {
                refreshCrashLog()
                crashLogTimerCancellable = crashLogTimer.connect()
            }
        }
        .onChange(of: isCrashLogExpanded) { expanded in
            if expanded {
                refreshCrashLog()
                crashLogTimerCancellable = crashLogTimer.connect()
            } else {
                crashLogTimerCancellable?.cancel()
                crashLogTimerCancellable = nil
            }
        }
        .onDisappear {
            crashLogTimerCancellable?.cancel()
            crashLogTimerCancellable = nil
        }
        .onReceive(crashLogTimer) { _ in refreshCrashLog() }
    }
}
