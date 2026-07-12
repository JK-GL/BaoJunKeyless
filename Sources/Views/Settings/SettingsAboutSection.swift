import SwiftUI

struct SettingsAboutSection: View {
    var body: some View {
        SettingsPanelView(title: "关于") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsStatusRowView(title: "应用名称", value: "SGMW Key")
                SettingsStatusRowView(title: "版本", value: AppInfo.pluginVersion)
                SettingsStatusRowView(title: "构建", value: AppInfo.buildDate)
                SettingsStatusRowView(title: "系统", value: AppInfo.systemVersion)
                SettingsStatusRowView(title: "说明", value: "支持五菱 / 宝骏手机车控与数字钥匙")
            }
        }
    }
}
