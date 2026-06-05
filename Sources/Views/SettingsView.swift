import SwiftUI

// MARK: - Settings View (Tab 4 — XMusic SettingsPanelView style)
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @AppStorage(AppThemePreset.storageKey) private var themeRaw = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) private var accentData = Data()
    @AppStorage(AppThemeStorage.customBackgroundRevisionKey) private var bgRevision = 0
    @AppStorage(AppThemeStorage.customBackgroundBlurKey) private var bgBlur = 0.0

    @State private var showingResetAlert = false
    @State private var toastText: String?
    @State private var isCustomEditorExpanded = false
    @State private var isPhotoPickerPresented = false
    @State private var isCrashLogExpanded = false

    private var currentTheme: AppThemeConfiguration {
        AppThemeConfiguration(selectedThemeRawValue: themeRaw, customAccentData: accentData,
                              customBackgroundRevision: bgRevision, customBackgroundBlur: bgBlur)
    }

    var body: some View {
        ZStack {
            AppBackgroundView()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeaderView(title: "设置")
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Theme Section
                    SettingsPanelView(title: "外观与皮肤", subtitle: "切换主题或设置自定义背景。") {
                        VStack(alignment: .leading, spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(AppThemePreset.allCases) { preset in
                                        Button {
                                            themeRaw = preset.rawValue
                                            if preset != .custom { isCustomEditorExpanded = false }
                                        } label: {
                                            ThemeOptionCardView(
                                                theme: themeConfig(for: preset),
                                                isSelected: currentTheme.preset == preset
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 1)
                            }

                            if currentTheme.preset == .custom {
                                customThemeEditor
                            }
                        }
                    }

                    // About Section
                    SettingsPanelView(title: "关于") {
                        VStack(alignment: .leading, spacing: 10) {
                            SettingsStatusRowView(
                                title: "插件版本",
                                value: "v1.0.0"
                            )
                            SettingsStatusRowView(
                                title: "构建号",
                                value: "2026.05.31"
                            )
                            SettingsStatusRowView(
                                title: "框架",
                                value: "Theos / Logos"
                            )
                            SettingsStatusRowView(
                                title: "越狱",
                                value: "Dopamine rootless"
                            )
                        }
                    }

                    // Crash Log（可折叠、可滚动）
                    CollapsibleCard(
                        title: "崩溃日志",
                        icon: "ladybug.fill",
                        iconColor: Color.red.opacity(0.85),
                        isExpanded: $isCrashLogExpanded,
                        headerExtra: {
                            HStack(spacing: 8) {
                                if CrashLogger.shared.readLog()?.isEmpty == false {
                                    Text("有记录")
                                        .font(.caption2)
                                        .foregroundStyle(Color.orange.opacity(0.9))
                                } else {
                                    Text("无记录")
                                        .font(.caption2)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }

                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { CrashLogger.shared.isLoggingEnabled },
                                        set: { CrashLogger.shared.isLoggingEnabled = $0 }
                                    )
                                )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .scaleEffect(0.7)
                            }
                        }
                    ) {
                        if let log = CrashLogger.shared.readLog(), !log.isEmpty {
                            ScrollView(.vertical, showsIndicators: true) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(log)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.62))
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
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

                            HStack(spacing: 12) {
                                Button(action: {
                                    UIPasteboard.general.string = log
                                    withAnimation { toastText = "已复制到剪贴板" }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 12))
                                        Text("复制")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(AppTheme.accent)
                                }

                                Button(action: {
                                    CrashLogger.shared.clearLog()
                                    withAnimation { toastText = "日志已清空" }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                        Text("清空")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(Color.red.opacity(0.8))
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.green)
                                Text("暂无崩溃记录")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                        }
                    }

                    // Reset Button
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

                    Spacer(minLength: 100)
                }
            }
            .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
            .onDisappear {
                scrollState.reset()
            }

            if let text = toastText {
                VStack { Spacer(); ToastView(text: text) }
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

    // MARK: - Custom Theme Editor
    private var customThemeEditor: some View {
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
                    Slider(value: $bgBlur, in: 0...36)
                        .frame(width: 160)
                        .tint(currentTheme.accent)
                    Text("\(Int(bgBlur))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.62))
                }

                Button("移除背景图") {
                    try? AppThemeStorage.removeBackgroundImage()
                    bgRevision += 1
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
        .sheet(isPresented: $isPhotoPickerPresented) {
            PhotoPicker { data in
                if let d = data {
                    try? AppThemeStorage.saveBackgroundImageData(d)
                    bgRevision += 1
                }
            }
        }
    }

    private var accentBinding: Binding<Color> {
        Binding(get: { currentTheme.customAccent },
                set: { accentData = AppThemeStorage.customAccentData(from: $0) })
    }

    private func themeConfig(for preset: AppThemePreset) -> AppThemeConfiguration {
        var data = accentData
        if preset != .custom { data = Data() }
        return AppThemeConfiguration(selectedThemeRawValue: preset.rawValue,
                                     customAccentData: data,
                                     customBackgroundRevision: bgRevision,
                                     customBackgroundBlur: bgBlur)
    }
}

// MARK: - Photo Picker
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            parent.onPick(img?.jpegData(compressionQuality: 0.8))
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
