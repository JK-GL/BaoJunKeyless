import SwiftUI

// MARK: - 震动选择类型
enum VibrationChoice: Hashable {
    case preset(VibrationPattern)
    case custom(UUID)
}

struct KeylessView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var settingsStore: KeylessSettingsStore
    @EnvironmentObject var customStore: CustomVibrationStore
    @EnvironmentObject var vehicleLog: VehicleEventLogStore

    @State private var showUnlockRecorder = false
    @State private var showLockRecorder = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "无感车控")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                KeylessMainSection(setMode: setMode)
                UnlockSettingsSection(
                    showRecorder: $showUnlockRecorder,
                    choice: unlockVibChoiceBinding,
                    customStore: customStore
                )
                LockSettingsSection(
                    showRecorder: $showLockRecorder,
                    choice: lockVibChoiceBinding,
                    customStore: customStore
                )

                Spacer(minLength: 100)
            }
        }
        .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
        .onDisappear {
            scrollState.reset()
        }
        .sheet(isPresented: $showUnlockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setUnlockVibChoice(.custom(pattern.id))
                vehicleLog.add(.keyless, "录制解锁震动", detail: pattern.name)
            }
        }
        .sheet(isPresented: $showLockRecorder) {
            VibrationRecorderView { pattern in
                customStore.add(pattern)
                settingsStore.setLockVibChoice(.custom(pattern.id))
                vehicleLog.add(.keyless, "录制上锁震动", detail: pattern.name)
            }
        }
    }

    private func setMode(_ mode: KeylessControlMode) {
        settingsStore.settings.pluginTakeover = (mode == .plugin)
        settingsStore.settings.smartSwitch = (mode == .smart)
        settingsStore.settings.appManual = (mode == .manual)

        let text: String
        switch mode {
        case .plugin: text = "插件托管"
        case .smart: text = "智能切换"
        case .manual: text = "App 手动"
        }
        vehicleLog.add(.keyless, "切换无感模式", detail: text)
    }

    private var unlockVibChoiceBinding: Binding<VibrationChoice> {
        Binding(
            get: { settingsStore.unlockVibChoice() },
            set: { settingsStore.setUnlockVibChoice($0) }
        )
    }

    private var lockVibChoiceBinding: Binding<VibrationChoice> {
        Binding(
            get: { settingsStore.lockVibChoice() },
            set: { settingsStore.setLockVibChoice($0) }
        )
    }
}
