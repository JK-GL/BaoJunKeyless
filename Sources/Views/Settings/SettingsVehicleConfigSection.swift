import SwiftUI

// MARK: - 车辆配置
struct SettingsVehicleConfigSection: View {
    private enum Style {
        static let outerRadius: CGFloat = 18
        static let innerRadius: CGFloat = 16
        static let outerFill = Color.white.opacity(0.04)
        static let outerStroke = Color.white.opacity(0.06)
        static let innerFill = Color.white.opacity(0.035)
        static let innerStroke = Color.white.opacity(0.05)
    }
    @EnvironmentObject var theme: ThemeManager
    let vehicleCredentials: VehicleCredentialsStore
    @StateObject private var viewModel: VehicleConfigViewModel
    @FocusState private var isTokenFieldFocused: Bool
    @Binding var toastText: String?
    let onSave: () -> Void
    let onCredentialConfirm: (CredentialConfirmPayload) -> Void

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

    var body: some View {
        SettingsPanelView(title: "车辆配置") {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(icon: "doc.text.fill", title: "凭证来源")

                        HStack(alignment: .center, spacing: 10) {
                            Text("导入方式")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.82))

                            Spacer(minLength: 8)

                            infoPill(icon: "doc.text.fill", text: viewModel.tokenSourceSummary)
                        }

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
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(AppTheme.accent.opacity(0.11))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .stroke(AppTheme.accent.opacity(0.22), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            sectionHeader(icon: "key.fill", title: "访问凭证")
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

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Token")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.55))

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
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Style.outerRadius, style: .continuous)
                    .fill(Style.outerFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Style.outerRadius, style: .continuous)
                    .stroke(Style.outerStroke, lineWidth: 1)
            )
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

    @ViewBuilder
    private var headerCard: some View {
        sectionCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.orange.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: "car.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppTheme.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isConfigured ? viewModel.currentVINText : "未配置车辆")
                        .font(.system(size: 16, weight: .semibold, design: viewModel.isConfigured ? .monospaced : .default))
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
                        .frame(width: 36, height: 36)
                    Image(systemName: viewModel.isConfigured ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(statusBadgeColor)
                }
                .accessibilityLabel(viewModel.statusBadgeText)
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                    .fill(Style.innerFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
                    .stroke(Style.innerStroke, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.orange)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(AppTheme.orange.opacity(0.14))
                )
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
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
