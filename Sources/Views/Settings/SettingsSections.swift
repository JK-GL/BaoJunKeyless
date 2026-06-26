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

struct SettingsAboutSection: View {
    var body: some View {
        SettingsPanelView(title: "关于") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsStatusRowView(title: "版本", value: AppInfo.pluginVersion)
                SettingsStatusRowView(title: "系统", value: AppInfo.systemVersion)
                SettingsStatusRowView(title: "框架", value: "SwiftUI / UIKit")
                SettingsStatusRowView(title: "日期", value: AppInfo.buildDate)
                SettingsStatusRowView(title: "越狱", value: AppInfo.jailbreakEnvironment)
            }
        }
    }
}

// MARK: - 车辆配置
struct SettingsVehicleConfigSection: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var vehicleCredentials: VehicleCredentialsStore
    @State private var accessTokenDraft: String = ""
    @State private var vinDraft: String = ""
    @State private var phoneDraft: String = ""
    @State private var isEditing = false
    @State private var isFetching = false
    @State private var showingImportGuide = false
    @Binding var toastText: String?
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28)) { isEditing.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .foregroundStyle(AppTheme.orange)
                        .font(.system(size: 15, weight: .semibold))
                    Text("车辆配置")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if vehicleCredentials.isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.green)
                            .font(.system(size: 13))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isEditing ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                Divider().background(theme.cardStroke)

                VStack(alignment: .leading, spacing: 12) {
                    // 快捷导入按钮
                    Button {
                        showingImportGuide = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 13))
                            Text("从五菱 App 导入凭据")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.white.opacity(0.08))

                    credentialField(
                        label: "Access Token",
                        placeholder: "从五菱/宝骏 App 的 SavedOAuthModel 获取",
                        text: $accessTokenDraft,
                        isSecure: true
                    )

                    if !vinDraft.isEmpty {
                        credentialField(label: "VIN", placeholder: "", text: .constant(vinDraft))
                            .disabled(true)
                        credentialField(label: "手机号", placeholder: "", text: .constant(phoneDraft))
                            .disabled(true)
                    }

                    Button {
                        fetchVehicleInfo()
                    } label: {
                        HStack(spacing: 6) {
                            if isFetching { ProgressView().scaleEffect(0.7) }
                            Text(isFetching ? "查询中…" : "填入 Token 后点这里查询车辆")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                    .disabled(accessTokenDraft.isEmpty || isFetching)

                    HStack(spacing: 12) {
                        Button {
                            vehicleCredentials.accessToken = accessTokenDraft
                            vehicleCredentials.vin = vinDraft
                            vehicleCredentials.phone = phoneDraft
                            toastText = "配置已保存，正在连接…"
                            onSave()
                        } label: {
                            Text("保存")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(vehicleCredentials.isConfigured ? AppTheme.green : Color.white.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!vehicleCredentials.isConfigured)

                        Button {
                            vehicleCredentials.reset()
                            accessTokenDraft = ""
                            vinDraft = ""
                            phoneDraft = ""
                            toastText = "配置已清除"
                        } label: {
                            Text("清除")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.red.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    if !vehicleCredentials.isConfigured {
                        Text("只需填入 access_token，VIN 和手机号会自动查询获取。")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.green)
                            Text("已配置 · \(vehicleCredentials.vin)")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.62))
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
            accessTokenDraft = vehicleCredentials.accessToken
            vinDraft = vehicleCredentials.vin
            phoneDraft = vehicleCredentials.phone
        }
        .sheet(isPresented: $showingImportGuide) {
            ImportGuideSheet()
        }
    }

    private func fetchVehicleInfo() {
        let token = accessTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isFetching = true
        SGMWApiClient.shared.queryDefaultCar(accessToken: token) { result in
            DispatchQueue.main.async {
                isFetching = false
                if let result {
                    vinDraft = result.vin
                    phoneDraft = result.phone
                    toastText = "车辆信息已获取"
                } else {
                    toastText = "查询失败，请检查 Token"
                }
            }
        }
    }

    @ViewBuilder
    private func credentialField(label: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.55))
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.white)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }
}

// MARK: - 导入凭据指引
struct ImportGuideSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var tokenDraft = ""
    @State private var vinDraft = ""
    @State private var phoneDraft = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("从五菱 App 导入凭据")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Group {
                        guideStep(num: 1, title: "打开 TrollStore 文件管理器", detail: "找到五菱 App 的 App Group 容器")
                        guideStep(num: 2, title: "复制 SavedOAuthModel", detail: "路径：group.com.cloudy.LingLingBang/SavedOAuthModel")
                        guideStep(num: 3, title: "粘贴到 /var/mobile/", detail: "直接粘贴到 var/mobile/ 目录下")
                        guideStep(num: 4, title: "返回 App 点击「读取」", detail: "App 会自动从 /var/mobile/SavedOAuthModel 读取")
                    }

                    Divider().background(Color.white.opacity(0.1))

                    Text("如果自动读取失败，请手动填入：")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.6))

                    VStack(spacing: 10) {
                        HStack {
                            Text("access_token:").font(.caption).foregroundStyle(.secondary)
                            TextField("粘贴 token", text: $tokenDraft)
                                .textFieldStyle(.plain)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        HStack {
                            Text("VIN:").font(.caption).foregroundStyle(.secondary)
                            TextField("LK6ADAH92RB765125", text: $vinDraft)
                                .textFieldStyle(.plain)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        HStack {
                            Text("手机号:").font(.caption).foregroundStyle(.secondary)
                            TextField("13800138000", text: $phoneDraft)
                                .textFieldStyle(.plain)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("读取") {
                        readFromDisk()
                        dismiss()
                    }
                }
            }
        }
    }

    private func guideStep(num: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(num)")
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Capsule().fill(AppTheme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(Color.white.opacity(0.5))
            }
        }
    }

    private func readFromDisk() {
        // 尝试从 /var/mobile/ 读取
        let path = "/var/mobile/SavedOAuthModel"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else { return }

        let store = VehicleCredentialsStore()
        store.accessToken = token
        store.vin = vinDraft
        store.phone = phoneDraft
    }
}

struct SettingsDiagnosticsSection: View {
    @EnvironmentObject var vehicleStore: VehicleStateStore
    @AppStorage(AppDiagnosticsSettings.quickActionsDebugModeKey) private var quickActionsDebugMode = true

    var body: some View {
        SettingsPanelView(
            title: "诊断与联调",
            subtitle: "收纳开发期调试入口，状态页保持正式车控界面。"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ToggleRow(
                    icon: "wrench.and.screwdriver",
                    label: "快捷操作联动状态",
                    isOn: $quickActionsDebugMode
                )

                Text("开启后，快捷操作会同步切换模拟车辆状态，用于 UI 联调；关闭后仅展示指令弹窗，不改动状态页。")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(Color.white.opacity(0.1))

                HStack {
                    Label("油量栏显示", systemImage: "fuelpump")
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Spacer()

                    Picker("", selection: $vehicleStore.fuelBarMode) {
                        ForEach(FuelBarMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Text("自动：根据车辆配置识别插混/纯电；强制显示/隐藏：手动覆盖识别结果。")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsResetSection: View {
    @Binding var showingResetAlert: Bool
    let onReset: () -> Void

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
        }
        .padding(.horizontal, 16)
    }
}

struct SettingsCrashLogSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var crashLogText: String
    @Binding var isCrashLogExpanded: Bool
    @Binding var toastText: String?
    let refreshCrashLog: () -> Void
    let copyRecentLog: () -> Void
    let exportCrashLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28)) { isCrashLogExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(Color.red.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold))
                    Text("错误日志")
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
                            Text("暂无错误记录")
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

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], alignment: .leading, spacing: 10) {
                        Button {
                            refreshCrashLog()
                            withAnimation { toastText = "日志已刷新" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("刷新")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            CrashLogger.shared.logCurrentStatus(tag: "manual")
                            refreshCrashLog()
                            withAnimation { toastText = "状态已记录" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 12))
                                Text("记录状态")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            copyRecentLog()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                Text("复制最近")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            exportCrashLog()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12))
                                Text("导出")
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
            }
        }
        .onChange(of: isCrashLogExpanded) { expanded in
            if expanded {
                refreshCrashLog()
            }
        }
    }
}
