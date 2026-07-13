import SwiftUI

// MARK: - 车辆配置（折叠组，单层卡片，无内嵌窗口）
struct SettingsVehicleConfigSection: View {
    @EnvironmentObject var theme: ThemeManager
    let vehicleCredentials: VehicleCredentialsStore
    @StateObject private var viewModel: VehicleConfigViewModel
    @FocusState private var isTokenFieldFocused: Bool
    @Binding var toastText: String?
    let onSave: () -> Void
    let onCredentialConfirm: (CredentialConfirmPayload) -> Void

    /// 默认展开：首次配置更方便；之后用户可折叠
    @AppStorage("Settings.vehicleConfigSectionExpanded") private var isExpanded = true

    init(
        vehicleCredentials: VehicleCredentialsStore,
        toastText: Binding<String?>,
        onSave: @escaping () -> Void,
        onCredentialConfirm: @escaping (CredentialConfirmPayload) -> Void
    ) {
        self.vehicleCredentials = vehicleCredentials
        self._toastText = toastText
        self.onSave = onSave
        self.onCredentialConfirm = onCredentialConfirm
        self._viewModel = StateObject(wrappedValue: VehicleConfigViewModel(credentials: vehicleCredentials))
    }

    private var statusBadgeColor: Color {
        viewModel.isConfigured ? AppTheme.green : Color.white.opacity(0.35)
    }

    /// 折叠时显示完整 VIN；展开时标题旁全隐（内容区已有 VIN）
    private var collapsedHeaderVIN: String {
        if viewModel.isConfigured {
            let vin = viewModel.currentVINText.trimmingCharacters(in: .whitespacesAndNewlines)
            return vin.isEmpty ? "未配置" : vin
        }
        return "未配置"
    }

    var body: some View {
        CollapsibleCard(
            title: "车辆配置",
            icon: "car.fill",
            iconColor: AppTheme.orange,
            isExpanded: $isExpanded,
            headerExtra: {
                // 展开：全隐；折叠：完整 VIN（或未配置）
                if !isExpanded {
                    Text(collapsedHeaderVIN)
                        .font(.system(
                            size: 11.5,
                            weight: .medium,
                            design: viewModel.isConfigured ? .monospaced : .default
                        ))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
            }
        ) {
            // 单层内容：不再套内层圆角「窗口」
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.orange.opacity(0.15))
                            .frame(width: 42, height: 42)
                        Image(systemName: "car.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.isConfigured ? viewModel.currentVINText : "未配置车辆")
                            .font(.system(size: 15, weight: .semibold, design: viewModel.isConfigured ? .monospaced : .default))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(viewModel.isConfigured ? "车辆已配置" : "等待配置车辆凭证")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .lineLimit(1)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    ZStack {
                        Circle()
                            .fill(statusBadgeColor.opacity(viewModel.isConfigured ? 0.18 : 0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: viewModel.isConfigured ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(statusBadgeColor)
                    }
                    .accessibilityLabel(viewModel.statusBadgeText)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.orange)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(AppTheme.orange.opacity(0.14))
                        )

                    Text("导入方式")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    infoPill(icon: "doc.text.fill", text: viewModel.tokenSourceSummary)
                }

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: viewModel.autoReadWulingToken ? "bolt.horizontal.circle.fill" : "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(viewModel.autoReadWulingToken ? AppTheme.accent : AppTheme.orange)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill((viewModel.autoReadWulingToken ? AppTheme.accent : AppTheme.orange).opacity(0.14))
                        )

                    Text("自动读取五菱 App 凭证")
                        .font(.system(size: 14, weight: .medium))
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
                            if shouldConnect {
                                presentCredentialConfirm()
                                onSave()
                            }
                        }
                    } else {
                        viewModel.showingFilePicker = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.autoReadWulingToken ? "arrow.down.circle.fill" : "folder.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(viewModel.autoReadWulingToken ? "立即读取五菱 App 凭证" : "选择凭证文件")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Token")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Spacer()
                        Button {
                            viewModel.fetchVehicleInfo { toast, shouldConnect in
                                toastText = toast
                                if shouldConnect {
                                    presentCredentialConfirm()
                                    onSave()
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if viewModel.isFetching { ProgressView().scaleEffect(0.7) }
                                Text(viewModel.isFetching ? "查询中…" : "查询车辆信息")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accent.opacity(0.10))
                            )
                        }
                        .buttonStyle(.plain)
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

                HStack(spacing: 12) {
                    Button {
                        viewModel.saveManualConfig { toast, shouldConnect in
                            toastText = toast
                            if shouldConnect {
                                presentCredentialConfirm()
                                onSave()
                            }
                        }
                        isTokenFieldFocused = false
                    } label: {
                        Text("保存")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
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
                            .padding(.vertical, 11)
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
                        if shouldConnect {
                            presentCredentialConfirm()
                            onSave()
                        }
                    }
                }
            })
            .environmentObject(vehicleCredentials)
        }
        .sheet(isPresented: $viewModel.showingFilePicker) {
            SimpleDocumentPicker { url in
                viewModel.importTokenFromSelectedFile(url: url) { toast, shouldConnect in
                    toastText = toast
                    if shouldConnect {
                        presentCredentialConfirm()
                        onSave()
                    }
                }
                viewModel.showingFilePicker = false
            }
        }
    }

    private func presentCredentialConfirm() {
        onCredentialConfirm(viewModel.credentialConfirmPayload)
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
