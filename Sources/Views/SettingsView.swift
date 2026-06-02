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
                        aboutSection
                        actionButtons
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 16)
                }
                .background(AppTheme.pageBg.ignoresSafeArea())

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

    private var aboutSection: some View {
        CardView(title: "关于", icon: "info.circle", iconColor: .secondary) {
            InfoRow(icon: "gearshape.fill", label: "插件版本", value: "v1.0.0", isMono: true)
            InfoRow(icon: "gearshape.fill", label: "构建号",   value: "2026.05.31", isMono: true)
            InfoRow(icon: "info.circle",    label: "框架",     value: "Theos / Logos")
            InfoRow(icon: "info.circle",    label: "越狱",     value: "Dopamine rootless", valueColor: AppTheme.green)
        }
    }

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
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13))
                    Text("重置全部设置").font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(AppTheme.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.red.opacity(0.3), lineWidth: 1))
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
