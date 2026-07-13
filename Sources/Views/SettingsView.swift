import SwiftUI
import UIKit

// MARK: - Settings View (Tab 4 — XMusic SettingsPanelView style)
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var keylessSettings: KeylessSettingsStore
    @EnvironmentObject var customVibrationStore: CustomVibrationStore
    @EnvironmentObject var vehicleCredentials: VehicleCredentialsStore
    @EnvironmentObject var vehicleStore: VehicleStateStore
    @EnvironmentObject var addressSettings: AddressServiceSettings
    @AppStorage(AppDiagnosticsSettings.vehicleControlRouteModeKey) private var vehicleControlRouteModeRaw = VehicleControlRouteMode.auto.rawValue

    @State private var showingResetAlert = false
    @State private var toastText: String?
    @State private var isPhotoPickerPresented = false
    @State private var isCrashLogExpanded = false
    @State private var crashLogText: String = ""
    @State private var sharePayload: SharePayload?
    @State private var credentialConfirmPayload: CredentialConfirmPayload?


    private var vehicleControlRouteModeBinding: Binding<VehicleControlRouteMode> {
        Binding(
            get: { VehicleControlRouteMode(rawValue: vehicleControlRouteModeRaw) ?? .auto },
            set: { vehicleControlRouteModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "设置")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                SettingsThemeSection(
                    isPhotoPickerPresented: $isPhotoPickerPresented
                )

                SettingsVehicleConfigSection(
                    vehicleCredentials: vehicleCredentials,
                    toastText: $toastText,
                    onSave: connectMQTTIfNeeded,
                    onCredentialConfirm: { payload in
                        withAnimation(PopupMotion.presentSpring) {
                            credentialConfirmPayload = payload
                        }
                    }
                )

                // 后台增强：默认折叠，点击标题展开；开关持久化到 KeylessSettingsStore
                SettingsBackgroundEnhancementSection()

                SettingsVehicleControlDebugSection(
                    routeMode: vehicleControlRouteModeBinding,
                    toastText: $toastText
                )

                SettingsFuelDisplaySection()

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
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.activityItems)
        }
        .overlay {
            if showingResetAlert {
                CustomAlertView(
                    title: "重置插件",
                    message: "将重置主题、背景图、无感车控和自定义震动。错误日志不会清空。",
                    confirmTitle: "确认重置",
                    confirmColor: .red,
                    onCancel: { withAnimation(PopupMotion.dismissEase) { showingResetAlert = false } },
                    onConfirm: {
                        withAnimation(PopupMotion.dismissEase) { showingResetAlert = false }
                        resetAllSettings()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(PopupMotion.transition)
            }
        }
        .overlay {
            if let payload = credentialConfirmPayload {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(PopupMotion.dismissEase) { credentialConfirmPayload = nil }
                    }

                SettingsCredentialConfirmPopup(payload: payload) {
                    withAnimation(PopupMotion.dismissEase) { credentialConfirmPayload = nil }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(PopupMotion.transition)
                .zIndex(10)
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
        .onChange(of: vehicleCredentials.accessToken) { _ in connectMQTTIfNeeded() }
        .onChange(of: vehicleCredentials.vin) { _ in connectMQTTIfNeeded() }
    }

    private func connectMQTTIfNeeded() {
        guard let mqttStore = vehicleStore as? MQTTVehicleStateStore else { return }
        if vehicleCredentials.isConfigured {
            mqttStore.start(with: vehicleCredentials)
        }
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
        sharePayload = SharePayload(activityItems: [url])
        refreshCrashLog()
    }

    private func resetAllSettings() {
        keylessSettings.reset()
        customVibrationStore.reset()
        theme.resetAppearance()
        AppDiagnosticsSettings.resetHiddenDiagnosticsToggles()
        VehicleBLEBindingStore.clear()
        addressSettings.reset()
        VehicleEventLogStore.shared.add(.system, "重置全部设置", detail: "错误日志保留")
        CrashLogger.shared.logCurrentStatus(tag: "reset")
        withAnimation { toastText = "设置已重置" }
    }
}
