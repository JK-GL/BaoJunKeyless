import SwiftUI

// MARK: - Settings View (Tab 4)
struct SettingsView: View {
    @Binding var isDarkMode: Bool
    @AppStorage(AppThemePreset.storageKey) private var themeRaw = AppThemePreset.midnight.rawValue
    @AppStorage(AppThemeStorage.customAccentDataKey) private var accentData = Data()
    @AppStorage(AppThemeStorage.customBackgroundRevisionKey) private var bgRevision = 0
    @AppStorage(AppThemeStorage.customBackgroundBlurKey) private var bgBlur = 0.0

    @State private var notifications = true
    @State private var globalVibrate = true
    @State private var autoStart = true
    @State private var showingResetAlert = false
    @State private var toastText: String?
    @State private var isCustomEditorExpanded = false
    @State private var isPhotoPickerPresented = false

    private var currentTheme: AppThemeConfiguration {
        AppThemeConfiguration(selectedThemeRawValue: themeRaw, customAccentData: accentData,
                              customBackgroundRevision: bgRevision, customBackgroundBlur: bgBlur)
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // ── Theme Section ──
                        themeSection
                        // ── General ──
                        generalSection
                        // ── About ──
                        aboutSection
                        // ── Actions ──
                        actionButtons
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .background(AppBackgroundView())

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
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Theme Section
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "paintbrush.fill").font(.system(size: 15)).foregroundColor(currentTheme.accent)
                Text("外观与皮肤").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("切换主题或设置自定义背景。")
                .font(.caption).foregroundColor(.white.opacity(0.5))

            // Theme selector scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
            }

            // Custom editor
            if currentTheme.preset == .custom {
                customThemeEditor
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var customThemeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Accent color picker
            HStack {
                Text("主色调").font(.caption).foregroundColor(.white.opacity(0.6))
                Spacer()
                ColorPicker("", selection: accentBinding)
                    .labelsHidden()
            }

            // Background image
            HStack {
                Text("背景图").font(.caption).foregroundColor(.white.opacity(0.6))
                Spacer()
                Button(currentTheme.hasCustomBackgroundImage ? "更换" : "选择图片") {
                    isPhotoPickerPresented = true
                }
                .font(.caption.weight(.medium))
                .foregroundColor(currentTheme.accent)
            }

            if currentTheme.hasCustomBackgroundImage {
                HStack {
                    Text("模糊度").font(.caption).foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Slider(value: $bgBlur, in: 0...36)
                        .frame(width: 160)
                        .tint(currentTheme.accent)
                    Text("\(Int(bgBlur))").font(.caption.monospacedDigit()).foregroundColor(.white.opacity(0.6))
                }

                Button("移除背景图") {
                    try? AppThemeStorage.removeBackgroundImage()
                    bgRevision += 1
                }
                .font(.caption).foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
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

    // MARK: - General
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill").font(.system(size: 15)).foregroundColor(.white.opacity(0.5))
                Text("通用设置").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            }
            HStack {
                Image(systemName: isDarkMode ? "moon.fill" : "moon")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.5)).frame(width: 22)
                Text("深色模式").font(.system(size: 15)).foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $isDarkMode).labelsHidden().tint(AppTheme.purple)
            }
            ToggleRow(icon: "bell.fill", label: "通知推送", isOn: $notifications)
            ToggleRow(icon: "flame.fill", label: "全局震动", isOn: $globalVibrate)
            ToggleRow(icon: "bolt.fill", label: "开机自启", isOn: $autoStart)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
    }

    // MARK: - About
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 15)).foregroundColor(.white.opacity(0.5))
                Text("关于").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            }
            InfoRow(icon: "gearshape.fill", label: "插件版本", value: "v1.0.0", isMono: true)
            InfoRow(icon: "gearshape.fill", label: "构建号", value: "2026.05.31", isMono: true)
            InfoRow(icon: "info.circle", label: "框架", value: "Theos / Logos")
            InfoRow(icon: "info.circle", label: "越狱", value: "Dopamine rootless", valueColor: AppTheme.green)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
    }

    // MARK: - Actions
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SettingsActionButton(icon: "square.and.arrow.up", label: "导出配置", color: .white.opacity(0.7)) {
                    withAnimation { toastText = "配置已导出" }
                }
                SettingsActionButton(icon: "square.and.arrow.down", label: "导入配置", color: .white.opacity(0.7)) {
                    withAnimation { toastText = "配置已导入" }
                }
            }
            Button(action: { showingResetAlert = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    Text("重置全部设置").font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).stroke(.red.opacity(0.3), lineWidth: 1))
            }
            .alert("重置插件", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) { }
                Button("确认重置", role: .destructive) { }
            } message: {
                Text("确定要重置全部插件数据吗？此操作不可撤销。")
            }
        }
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
