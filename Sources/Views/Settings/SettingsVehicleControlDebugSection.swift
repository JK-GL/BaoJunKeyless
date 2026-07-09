import SwiftUI

struct SettingsVehicleControlDebugSection: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var vehicleStore: VehicleStateStore
    @Binding var routeMode: VehicleControlRouteMode
    @Binding var toastText: String?
    @State private var binding = VehicleBLEBindingStore.load()

    private var mqttStore: MQTTVehicleStateStore? {
        vehicleStore as? MQTTVehicleStateStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .font(.system(size: 15, weight: .semibold))
                Text("车控调试")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("仅影响解锁/上锁/启动/熄火")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(VehicleControlRouteMode.allCases, id: \.rawValue) { mode in
                    Button {
                        routeMode = mode
                        NotificationCenter.default.post(name: .vehicleControlRouteModeChanged, object: nil)
                        withAnimation { toastText = "车控路由：\(mode.title)" }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: routeMode == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(routeMode == mode ? theme.accent : Color.white.opacity(0.35))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(mode.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(routeMode == mode ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(routeMode == mode ? theme.accent.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: binding == nil ? "link.badge.plus" : "link.circle.fill")
                        .foregroundStyle(binding == nil ? Color.white.opacity(0.45) : AppTheme.green)
                    Text("蓝牙绑定")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if binding != nil {
                        Button("清除绑定") {
                            VehicleBLEBindingStore.clear()
                            binding = nil
                            NotificationCenter.default.post(name: .vehicleControlRouteModeChanged, object: nil)
                            withAnimation { toastText = "已清除蓝牙绑定" }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                    }
                }

                Text(binding?.displaySummary ?? "尚未绑定。首次 BLE 鉴权成功后会自动绑定，下次优先直连。")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            if let mqttStore {
                bleDiagnosticsCard(mqttStore)
            }

            Text("建议排错顺序：先“强制BLE”复现连接/回包问题，再切“强制HTTP”对比云控链路，最后回到“自动”。")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .onAppear { binding = VehicleBLEBindingStore.load() }
    }

    @ViewBuilder
    private func bleDiagnosticsCard(_ store: MQTTVehicleStateStore) -> some View {
        let rows: [(String, String)] = [
            ("BLE状态", bleStatusText(store.bleStatus)),
            ("当前阶段", store.bleDiagnosticPhaseText),
            ("阶段详情", store.bleDiagnosticDetailText),
            ("最近结论", "\(store.bleDiagnosticLastConclusionText) · \(store.bleDiagnosticLastConclusionAtText)"),
            ("分类统计", store.bleDiagnosticCountsSummaryText),
            ("连续超时", "\(store.consecutiveScanTimeouts)"),
            ("扫描间隙", "\(Int(store.effectiveScanRetryInterval(baseInterval: store.keylessSettingsStore.settings.bleScanInterval)))s"),
            ("当前作用域", cacheScopeText(store)),
            ("当前BLE", bleKeySummaryText(store))
        ]

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wave.3.right.circle")
                    .foregroundStyle(AppTheme.accent)
                Text("BLE 诊断")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(store.bleStatus == .authenticated ? "活跃" : "观察中")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.0)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 64, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func bleStatusText(_ status: MQTTVehicleStateStore.LiveBLEStatus) -> String {
        switch status {
        case .disconnected: return "disconnected"
        case .scanning: return "scanning"
        case .connecting: return "connecting"
        case .authenticating: return "authenticating"
        case .authenticated: return "authenticated"
        case .error: return "error"
        }
    }

    private func cacheScopeText(_ store: MQTTVehicleStateStore) -> String {
        let phone = store.credentialsStore.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let vin = store.credentialsStore.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneText = phone.isEmpty ? "--" : String(phone.suffix(4))
        let vinText = vin.isEmpty ? "--" : String(vin.suffix(6))
        return "phone=\(phoneText) · vin=\(vinText)"
    }

    private func bleKeySummaryText(_ store: MQTTVehicleStateStore) -> String {
        let mac = store.latestBleKeyInfo["bleMac"] ?? store.latestBleKeyInfo["macAddress"] ?? "--"
        let keyId = store.latestBleKeyInfo["keyId"] ?? "--"
        return "keyId=\(keyId) · mac=\(mac)"
    }
}
