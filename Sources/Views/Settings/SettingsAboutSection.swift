import SwiftUI

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
