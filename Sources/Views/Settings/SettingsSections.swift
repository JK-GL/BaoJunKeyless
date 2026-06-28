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
    @State private var isFetching = false
    @State private var showingImportGuide = false
    @State private var showingFilePicker = false
    @State private var showingVehicleInfoConfirm = false
    @State private var queriedVehicleName = ""
    @State private var isEditingToken = false
    @FocusState private var isTokenFieldFocused: Bool
    @Binding var toastText: String?
    let onSave: () -> Void

    private var tokenSourceSummary: String {
        let label = vehicleCredentials.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = vehicleCredentials.tokenSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty && path.isEmpty {
            return vehicleCredentials.autoReadWulingToken ? "五菱 App 自动读取" : "手动输入 / 手动导入"
        }
        if label.isEmpty { return path }
        if path.isEmpty { return label }
        return label
    }

    private var tokenFieldDisplayText: String {
        let source = isEditingToken ? accessTokenDraft : (accessTokenDraft.isEmpty ? vehicleCredentials.accessToken : accessTokenDraft)
        return isEditingToken ? source : maskToken(source)
    }

    private var currentVINText: String {
        let value = vinDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        let stored = vehicleCredentials.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? "未配置" : stored
    }

    private var currentUserText: String {
        let value = phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        let stored = vehicleCredentials.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? "未配置" : stored
    }

    private var statusBadgeText: String {
        vehicleCredentials.isConfigured ? "已配置" : "未配置"
    }

    private var statusBadgeColor: Color {
        vehicleCredentials.isConfigured ? AppTheme.green : Color.white.opacity(0.35)
    }

    var body: some View {
        SettingsPanelView(title: "车辆配置", subtitle: "自动读取五菱 App 或手动导入 SavedOAuthModel。") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.orange.opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: "car.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppTheme.orange)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(vehicleCredentials.isConfigured ? currentVINText : "未配置车辆")
                                .font(.system(size: 16, weight: .semibold, design: vehicleCredentials.isConfigured ? .monospaced : .default))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Text(tokenSourceSummary)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        Text(statusBadgeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(vehicleCredentials.isConfigured ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(vehicleCredentials.isConfigured ? statusBadgeColor : statusBadgeColor.opacity(0.16))
                            )
                    }

                    HStack(spacing: 10) {
                        summaryChip(title: "用户", value: currentUserText, mono: true)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 12) {
                    ToggleRow(
                        icon: "arrow.trianglehead.2.clockwise.rotate.90",
                        label: "自动读取五菱 App Token",
                        isOn: $vehicleCredentials.autoReadWulingToken
                    )

                    Button {
                        if vehicleCredentials.autoReadWulingToken {
                            autoImportFromWulingApp()
                        } else {
                            showingFilePicker = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: vehicleCredentials.autoReadWulingToken ? "bolt.horizontal.circle.fill" : "folder.fill")
                                .font(.system(size: 13))
                            Text(vehicleCredentials.autoReadWulingToken ? "立即读取五菱 App 凭据" : "手动选择 SavedOAuthModel")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Text(vehicleCredentials.autoReadWulingToken ? "默认自动读取五菱 App 的 SavedOAuthModel；关闭后可手动选择文件。" : "已关闭自动读取，请手动选择 SavedOAuthModel 或粘贴 token。")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.55))

                    TextField("从五菱 App 的 SavedOAuthModel 获取", text: Binding(
                        get: { tokenFieldDisplayText },
                        set: { accessTokenDraft = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isTokenFieldFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isEditingToken = true
                            accessTokenDraft = vehicleCredentials.accessToken.isEmpty ? accessTokenDraft : vehicleCredentials.accessToken
                            isTokenFieldFocused = true
                        }
                    }
                    .onChange(of: isTokenFieldFocused) { focused in
                        if !focused {
                            isEditingToken = false
                        }
                    }
                }

                Button {
                    fetchVehicleInfo()
                } label: {
                    HStack(spacing: 6) {
                        if isFetching { ProgressView().scaleEffect(0.7) }
                        Text(isFetching ? "查询中…" : "查询车辆并确认用户信息")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .disabled(accessTokenDraft.isEmpty || isFetching)

                HStack(spacing: 12) {
                    Button {
                        let token = accessTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !token.isEmpty, !vinDraft.isEmpty else {
                            toastText = "请先查询车辆信息"
                            return
                        }
                        vehicleCredentials.accessToken = token
                        vehicleCredentials.vin = vinDraft
                        vehicleCredentials.phone = phoneDraft
                        isEditingToken = false
                        isTokenFieldFocused = false
                        if vehicleCredentials.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            vehicleCredentials.tokenSourceLabel = "手动输入 Token"
                        }
                        toastText = "配置已保存 · \(vinDraft)"
                        onSave()
                    } label: {
                        Text("保存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill((accessTokenDraft.isEmpty || vinDraft.isEmpty) ? Color.white.opacity(0.3) : AppTheme.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(accessTokenDraft.isEmpty || vinDraft.isEmpty || isFetching)

                    Button {
                        vehicleCredentials.reset()
                        accessTokenDraft = ""
                        vinDraft = ""
                        phoneDraft = ""
                        queriedVehicleName = ""
                        isEditingToken = false
                        isTokenFieldFocused = false
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
            }
        }
        .onAppear {
            accessTokenDraft = vehicleCredentials.accessToken
            vinDraft = vehicleCredentials.vin
            phoneDraft = vehicleCredentials.phone
            isEditingToken = false
            isTokenFieldFocused = false
        }
        .sheet(isPresented: $showingImportGuide) {
            ImportGuideSheet(onImported: {
                accessTokenDraft = vehicleCredentials.accessToken
                vinDraft = vehicleCredentials.vin
                phoneDraft = vehicleCredentials.phone
                toastText = vehicleCredentials.accessToken.isEmpty ? "未读取到 Token" : "已从文件读取 Token"
                if !vehicleCredentials.accessToken.isEmpty {
                    fetchVehicleInfo()
                }
            })
            .environmentObject(vehicleCredentials)
        }
        .sheet(isPresented: $showingFilePicker) {
            SimpleDocumentPicker { url in
                importTokenFromSelectedFile(url: url)
                showingFilePicker = false
            }
        }
        .overlay {
            if showingVehicleInfoConfirm {
                CustomAlertView(
                    title: queriedVehicleName.isEmpty ? "车辆信息确认" : queriedVehicleName,
                    message: "VIN：\(vinDraft)\n用户：\(phoneDraft.isEmpty ? "--" : phoneDraft)",
                    confirmTitle: "确认",
                    confirmColor: .green,
                    onCancel: { withAnimation(.easeOut(duration: 0.2)) { showingVehicleInfoConfirm = false } },
                    onConfirm: { withAnimation(.easeOut(duration: 0.2)) { showingVehicleInfoConfirm = false } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func autoImportFromWulingApp() {
        if let tokenInfo = SGMWApiClient.shared.readLocalTokenInfo() {
            accessTokenDraft = tokenInfo.token
            vehicleCredentials.accessToken = tokenInfo.token
            vehicleCredentials.tokenSourceLabel = "五菱 App 自动读取"
            vehicleCredentials.tokenSourcePath = tokenInfo.sourcePath
            isEditingToken = false
            isTokenFieldFocused = false
            toastText = "已自动读取五菱 Token"
            fetchVehicleInfo()
        } else {
            toastText = "自动读取失败，可切换为手动选择文件"
            showingImportGuide = true
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
                    vehicleCredentials.accessToken = token
                    vehicleCredentials.vin = result.vin
                    vehicleCredentials.phone = result.phone
                    isEditingToken = false
                    isTokenFieldFocused = false
                    if vehicleCredentials.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        vehicleCredentials.tokenSourceLabel = vehicleCredentials.autoReadWulingToken ? "五菱 App 自动读取" : "手动输入 Token"
                    }
                    queriedVehicleName = "车辆信息确认"
                    showingVehicleInfoConfirm = true
                    toastText = "车辆信息已获取并保存"
                    onSave()
                } else {
                    toastText = "查询失败，请检查 Token"
                }
            }
        }
    }

    private func importTokenFromSelectedFile(url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            toastText = "读取文件失败"
            return
        }
        let token = (json["access_token"] as? String)
            ?? ((json["data"] as? [String: Any])?["access_token"] as? String)
        guard let token, !token.isEmpty else {
            toastText = "文件中未找到 access_token"
            return
        }
        accessTokenDraft = token
        vehicleCredentials.accessToken = token
        vehicleCredentials.tokenSourceLabel = "手动导入 SavedOAuthModel"
        vehicleCredentials.tokenSourcePath = url.path
        isEditingToken = false
        isTokenFieldFocused = false
        toastText = "已从文件导入 Token"
        fetchVehicleInfo()
    }

    private func maskToken(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "未读取" }
        guard token.count > 12 else { return token }
        let prefix = token.prefix(6)
        let suffix = token.suffix(6)
        return "\(prefix)******\(suffix)"
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

    @ViewBuilder
    private func summaryChip(title: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(value)
                .font(.system(size: mono ? 12 : 13, weight: .semibold, design: mono ? .monospaced : .default))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

struct SettingsFuelDisplaySection: View {
    @EnvironmentObject var vehicleStore: VehicleStateStore

    var body: some View {
        SettingsPanelView(title: "油量显示", subtitle: "控制状态页是否显示油量。") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    fuelModeButton(.auto, title: "自动")
                    fuelModeButton(.show, title: "强制显示")
                    fuelModeButton(.hide, title: "强制隐藏")
                }

                Text("自动：根据车辆配置识别插混/纯电；强制显示/隐藏：手动覆盖结果。")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func fuelModeButton(_ mode: FuelBarMode, title: String) -> some View {
        let selected = vehicleStore.fuelBarMode == mode
        Button {
            vehicleStore.setFuelBarMode(mode)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? AppTheme.orange : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 导入凭据指引
struct ImportGuideSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vehicleCredentials: VehicleCredentialsStore
    let onImported: () -> Void
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
                        guideStep(num: 1, title: "默认自动读取五菱 App", detail: "开启自动读取后，App 会优先通过 App Group 直接读取 SavedOAuthModel")
                        guideStep(num: 2, title: "读取失败再手动选择文件", detail: "关闭自动读取后，可手动选择导出的 SavedOAuthModel 文件")
                        guideStep(num: 3, title: "导入后自动查询车辆", detail: "会自动查询 VIN 和用户信息，方便你确认")
                        guideStep(num: 4, title: "无需手动复制到 /var/mobile", detail: "现在优先尝试五菱 AppGroup 原路径，不再要求你手动拷贝")
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
        if let tokenInfo = SGMWApiClient.shared.readLocalTokenInfo() {
            vehicleCredentials.accessToken = tokenInfo.token
            vehicleCredentials.tokenSourceLabel = "五菱 App 自动读取"
            vehicleCredentials.tokenSourcePath = tokenInfo.sourcePath
            onImported()
        }
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
