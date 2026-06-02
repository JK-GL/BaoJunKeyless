import SwiftUI

// MARK: - Settings View (Tab 4)
struct SettingsView: View {
    @Binding var isDarkMode: Bool
    @State private var notifications = true
    @State private var globalVibrate = true
    @State private var autoStart = true
    @State private var showingResetAlert = false
    @State private var toastText: String?

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        generalSection
                        vehicleInfoSection
                        aboutSection
                        actionButtons
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 16)
                }
                .background(AppTheme.pageBg.ignoresSafeArea())

                // Toast overlay
                if let text = toastText {
                    VStack {
                        Spacer()
                        ToastView(text: text)
                    }
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
        }
        .navigationViewStyle(.stack)
    }

    // MARK: General
    private var generalSection: some View {
        CardView(title: "通用设置", icon: "gearshape.fill", iconColor: .secondary) {
            HStack {
                Image(systemName: isDarkMode ? "moon.fill" : "moon")
                    .font(.system(size: 14)).foregroundColor(.secondary).frame(width: 22)
                Text("深色模式").font(.system(size: 15))
                Spacer()
                Toggle("", isOn: $isDarkMode).labelsHidden().tint(AppTheme.purple)
            }
            ToggleRow(icon: "bell.fill", label: "通知推送", isOn: $notifications)
            ToggleRow(icon: "flame.fill", label: "全局震动", isOn: $globalVibrate)
            ToggleRow(icon: "bolt.fill", label: "开机自启", isOn: $autoStart)
        }
    }

    // MARK: Vehicle Info
    private var vehicleInfoSection: some View {
        CardView(title: "车辆信息", icon: "car.fill", iconColor: AppTheme.accent) {
            InfoRow(icon: "info.circle", label: "车型",     value: "宝骏云海 140km PHEV")
            InfoRow(icon: "info.circle", label: "VIN",      value: "LK6ADAH92RB765125", isMono: true)
            InfoRow(icon: "bolt.fill",   label: "BLE 设备",  value: "E260-BLE", valueColor: AppTheme.accent)
            InfoRow(icon: "wifi",        label: "MAC",       value: "CC:45:A5:DA:B5:C3", isMono: true, valueColor: AppTheme.accent)
            InfoRow(icon: "key.fill",    label: "Key ID",    value: "1123037", isMono: true, valueColor: AppTheme.accent)
            InfoRow(icon: "shield.fill", label: "钥匙类型",  value: "车主钥匙", valueColor: AppTheme.green)
            InfoRow(icon: "gauge.medium",label: "提供商",    value: "德赛 (desai)")
        }
    }

    // MARK: About
    private var aboutSection: some View {
        CardView(title: "关于", icon: "info.circle", iconColor: .secondary) {
            InfoRow(icon: "gearshape.fill", label: "插件版本", value: "v1.0.0", isMono: true)
            InfoRow(icon: "gearshape.fill", label: "构建号",   value: "2026.05.31", isMono: true)
            InfoRow(icon: "info.circle",    label: "框架",     value: "Theos / Logos")
            InfoRow(icon: "info.circle",    label: "越狱",     value: "Dopamine rootless", valueColor: AppTheme.green)
        }
    }

    // MARK: Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SettingsActionButton(icon: "square.and.arrow.up", label: "导出配置", color: AppTheme.accent) {
                    withAnimation { toastText = "配置已导出" }
                }
                SettingsActionButton(icon: "square.and.arrow.down", label: "导入配置", color: AppTheme.accent) {
                    withAnimation { toastText = "配置已导入" }
                }
            }

            Button(action: { showingResetAlert = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                    Text("重置全部设置")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(AppTheme.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.red.opacity(0.3), lineWidth: 1)
                )
            }
            .alert("重置插件", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) { }
                Button("确认重置", role: .destructive) { }
            } message: {
                Text("确定要重置全部插件数据吗？此操作不可撤销。")
            }
        }
        .padding(.horizontal, 16)
    }
}
