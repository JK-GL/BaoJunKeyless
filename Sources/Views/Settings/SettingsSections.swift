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
    let vehicleCredentials: VehicleCredentialsStore
    @StateObject private var viewModel: VehicleConfigViewModel
    @FocusState private var isTokenFieldFocused: Bool
    @Binding var toastText: String?
    let onSave: () -> Void

    init(vehicleCredentials: VehicleCredentialsStore, toastText: Binding<String?>, onSave: @escaping () -> Void) {
        self.vehicleCredentials = vehicleCredentials
        self._toastText = toastText
        self.onSave = onSave
        self._viewModel = StateObject(wrappedValue: VehicleConfigViewModel(credentials: vehicleCredentials))
    }

    private var statusBadgeColor: Color {
        viewModel.isConfigured ? AppTheme.green : Color.white.opacity(0.35)
    }

    var body: some View {
        SettingsPanelView(title: "车辆配置") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.orange.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: "car.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(AppTheme.orange)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.isConfigured ? viewModel.currentVINText : "未配置车辆")
                                .font(.system(size: 16, weight: .semibold, design: viewModel.isConfigured ? .monospaced : .default))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            HStack(spacing: 8) {
                                infoPill(icon: "person.fill", text: viewModel.currentUserText, mono: true)
                                infoPill(icon: "doc.text.fill", text: viewModel.tokenSourceSummary)
                            }
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 0)

                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(statusBadgeColor.opacity(viewModel.isConfigured ? 0.18 : 0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: viewModel.isConfigured ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(statusBadgeColor)
                            }

                            Text(viewModel.statusBadgeText)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(statusBadgeColor)
                        }
                        .accessibilityLabel(viewModel.statusBadgeText)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: viewModel.autoReadWulingToken ? "bolt.horizontal.circle.fill" : "folder.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(viewModel.autoReadWulingToken ? AppTheme.accent : AppTheme.orange)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill((viewModel.autoReadWulingToken ? AppTheme.accent : AppTheme.orange).opacity(0.14))
                            )

                        Text("自动读取五菱 App 凭证")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer(minLength: 8)

                        Toggle("", isOn: Binding(
                            get: { viewModel.autoReadWulingToken },
                            set: { viewModel.autoReadWulingToken = $0 }
                        ))
                        .labelsHidden()
                        .tint(theme.accent)
                    }

                    Button {
                        if viewModel.autoReadWulingToken {
                            viewModel.autoImportFromWulingApp { toast, shouldConnect in
                                toastText = toast
                                if shouldConnect { onSave() }
                            }
                        } else {
                            viewModel.showingFilePicker = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.autoReadWulingToken ? "arrow.down.circle.fill" : "folder.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text(viewModel.autoReadWulingToken ? "立即读取五菱 App 凭证" : "选择凭证文件")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.11))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
                                )
                        }
                    }
                    .buttonStyle(.plain)
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

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Token")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Spacer()
                        Button {
                            viewModel.fetchVehicleInfo { toast, shouldConnect in
                                toastText = toast
                                if shouldConnect { onSave() }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if viewModel.isFetching { ProgressView().scaleEffect(0.7) }
                                Text(viewModel.isFetching ? "查询中…" : "查询车辆信息")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }
                        .disabled(viewModel.accessTokenDraft.isEmpty || viewModel.isFetching)
                    }

                    TextField("粘贴或自动读取 Token", text: Binding(
                        get: { viewModel.tokenFieldDisplayText },
                        set: { viewModel.accessTokenDraft = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isTokenFieldFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewModel.beginTokenEditing()
                            isTokenFieldFocused = true
                        }
                    }
                    .onChange(of: isTokenFieldFocused) { focused in
                        if !focused {
                            viewModel.endTokenEditing()
                        }
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

                HStack(spacing: 12) {
                    Button {
                        viewModel.saveManualConfig { toast, shouldConnect in
                            toastText = toast
                            if shouldConnect { onSave() }
                        }
                        isTokenFieldFocused = false
                    } label: {
                        Text("保存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill((viewModel.accessTokenDraft.isEmpty || viewModel.vinDraft.isEmpty) ? Color.white.opacity(0.3) : AppTheme.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.accessTokenDraft.isEmpty || viewModel.vinDraft.isEmpty || viewModel.isFetching)

                    Button {
                        viewModel.clear { toast, _ in
                            toastText = toast
                        }
                        isTokenFieldFocused = false
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
            viewModel.syncFromStore()
            isTokenFieldFocused = false
        }
        .sheet(isPresented: $viewModel.showingImportGuide) {
            ImportGuideSheet(onImported: {
                viewModel.syncFromStore()
                toastText = vehicleCredentials.accessToken.isEmpty ? "未读取到 Token" : "已从文件读取 Token"
                if !vehicleCredentials.accessToken.isEmpty {
                    viewModel.fetchVehicleInfo { toast, shouldConnect in
                        toastText = toast
                        if shouldConnect { onSave() }
                    }
                }
            })
            .environmentObject(vehicleCredentials)
        }
        .sheet(isPresented: $viewModel.showingFilePicker) {
            SimpleDocumentPicker { url in
                viewModel.importTokenFromSelectedFile(url: url) { toast, shouldConnect in
                    toastText = toast
                    if shouldConnect { onSave() }
                }
                viewModel.showingFilePicker = false
            }
        }
        .overlay {
            if viewModel.showingVehicleInfoConfirm {
                CustomAlertView(
                    title: viewModel.queriedVehicleName.isEmpty ? "车辆信息确认" : viewModel.queriedVehicleName,
                    message: "VIN：\(viewModel.vinDraft)\n用户：\(viewModel.phoneDraft.isEmpty ? "--" : viewModel.phoneDraft)",
                    confirmTitle: "确认",
                    confirmColor: .green,
                    onCancel: { withAnimation(.easeOut(duration: 0.2)) { viewModel.showingVehicleInfoConfirm = false } },
                    onConfirm: { withAnimation(.easeOut(duration: 0.2)) { viewModel.showingVehicleInfoConfirm = false } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func infoPill(icon: String, text: String, mono: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.055))
        )
    }
}

struct SettingsFuelDisplaySection: View {
    @EnvironmentObject var vehicleStore: VehicleStateStore

    var body: some View {
        SettingsPanelView(title: "油量显示") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    fuelModeButton(.auto, title: "自动")
                    fuelModeButton(.show, title: "强制显示")
                    fuelModeButton(.hide, title: "强制隐藏")
                }
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
