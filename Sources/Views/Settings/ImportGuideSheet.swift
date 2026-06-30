import SwiftUI

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
