import SwiftUI

/// 设置页「后台增强」折叠组：默认折叠，点击标题展开；开关持久化并接线 BackgroundExecutionManager。
struct SettingsBackgroundEnhancementSection: View {
    @EnvironmentObject var keylessSettings: KeylessSettingsStore

    private var keylessOn: Bool { keylessSettings.settings.keylessEnabled }
    private var controlsEnabled: Bool { keylessOn }
    private var geofenceOn: Bool { keylessSettings.settings.geofenceWakeEnabled }

    private var summaryText: String {
        keylessSettings.settings.backgroundEnhancementSummary(keylessEnabled: keylessOn)
    }

    var body: some View {
        CollapsibleCard(
            title: "后台增强",
            icon: "moon.zzz.fill",
            iconColor: AppTheme.purple,
            isExpanded: Binding(
                get: { keylessSettings.settings.backgroundSectionExpanded },
                set: { keylessSettings.settings.backgroundSectionExpanded = $0 }
            ),
            headerExtra: {
                Text(summaryText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("用于提升锁屏/切后台时的无感成功率。电子围栏只负责靠近时唤醒，不会单独解锁或上锁。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                if !keylessOn {
                    Text("无感关闭时，本组功能暂停生效；已选设置会保留。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                backgroundToggle(
                    icon: "bolt.horizontal.circle",
                    title: "增强后台执行",
                    subtitle: "锁屏或切到后台后，继续执行无感相关任务",
                    isOn: binding(\.backgroundEnhancedEnabled, log: "增强后台执行"),
                    enabled: controlsEnabled
                )

                backgroundToggle(
                    icon: "location.circle",
                    title: "电子围栏预唤醒",
                    subtitle: "靠近车辆区域时自动启动蓝牙警戒，远离后降低功耗",
                    isOn: binding(\.geofenceWakeEnabled, log: "电子围栏预唤醒"),
                    enabled: controlsEnabled
                )

                if geofenceOn {
                    VStack(alignment: .leading, spacing: 6) {
                        SliderRow(
                            icon: "circle.dashed",
                            label: "围栏半径",
                            value: Binding(
                                get: { keylessSettings.settings.geofenceRadiusMeters },
                                set: { newValue in
                                    let clamped = KeylessSettings.clampedGeofenceRadius(newValue)
                                    keylessSettings.settings.geofenceRadiusMeters = clamped
                                }
                            ),
                            range: 50...500,
                            step: 10,
                            format: "\(Int(keylessSettings.settings.geofenceRadiusMeters)) 米",
                            tint: AppTheme.purple
                        ) { value in
                            VehicleEventLogStore.shared.add(
                                .keyless,
                                "修改围栏半径",
                                detail: "\(Int(KeylessSettings.clampedGeofenceRadius(value))) 米"
                            )
                        }
                        .disabled(!controlsEnabled)
                        .opacity(controlsEnabled ? 1 : 0.45)

                        Text("靠近多少米内开始蓝牙警戒；过小可能不触发，过大更早唤醒。围栏只负责预唤醒，不直接解锁/上锁。")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    // 仅围栏内扫描：依赖电子围栏
                    VStack(alignment: .leading, spacing: 6) {
                        backgroundToggle(
                            icon: "antenna.radiowaves.left.and.right.slash",
                            title: "仅围栏内扫描",
                            subtitle: "开启后：围栏外几乎不扫蓝牙，进入围栏才开始警戒扫描；关闭则保持现状（未连上时持续周期扫描）。前台与后台统一。",
                            isOn: binding(\.scanOnlyInsideGeofence, log: "仅围栏内扫描"),
                            enabled: controlsEnabled
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                backgroundToggle(
                    icon: "location.fill",
                    title: "定位保活",
                    subtitle: "无感警戒期间借助定位延长后台存活（会增加耗电）",
                    isOn: binding(\.locationKeepAliveEnabled, log: "定位保活"),
                    enabled: controlsEnabled
                )

                backgroundToggle(
                    icon: "arrow.triangle.2.circlepath",
                    title: "后台状态同步",
                    subtitle: "后台保持车况同步，并为省电自动降频",
                    isOn: binding(\.backgroundStateSyncEnabled, log: "后台状态同步"),
                    enabled: controlsEnabled
                )

                Text("无感结果通知沿用无感页的解锁/上锁弹窗开关。不会夸大为永久后台；系统省电策略仍可能限制执行，请保留必要定位/蓝牙权限。")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<KeylessSettings, Bool>, log title: String) -> Binding<Bool> {
        Binding(
            get: { keylessSettings.settings[keyPath: keyPath] },
            set: { newValue in
                keylessSettings.settings[keyPath: keyPath] = newValue
                VehicleEventLogStore.shared.add(
                    .keyless,
                    newValue ? "开启\(title)" : "关闭\(title)"
                )
            }
        )
    }

    @ViewBuilder
    private func backgroundToggle(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        enabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ToggleRow(icon: icon, label: title, isOn: isOn)
                .disabled(!enabled)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.50))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 30)
        }
        .opacity(enabled ? 1 : 0.45)
    }
}
