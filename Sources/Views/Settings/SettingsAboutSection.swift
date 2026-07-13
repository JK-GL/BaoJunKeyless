import SwiftUI

struct SettingsAboutSection: View {
    var body: some View {
        SettingsPanelView(title: "关于") {
            VStack(alignment: .leading, spacing: 10) {
                // 精简：不要应用名称 / 说明
                SettingsStatusRowView(title: "版本", value: AppInfo.pluginVersion)
                SettingsStatusRowView(title: "构建", value: AppInfo.buildDate)
                SettingsStatusRowView(title: "系统", value: AppInfo.systemVersion)
            }
        }
    }
}
