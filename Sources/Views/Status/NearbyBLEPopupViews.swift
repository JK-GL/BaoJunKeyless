import SwiftUI

struct NearbyBLEDevicesLaunchButton: View {
    @ObservedObject var nearbyStore: NearbyBLEDevicesStore
    let action: () -> Void

    var body: some View {
        PopupActionGridButton(
            title: "附近设备",
            icon: "dot.radiowaves.left.and.right",
            tint: AppTheme.orange,
            badgeText: nearbyStore.count > 0 ? "\(nearbyStore.count)" : nil,
            action: action
        )
    }
}

struct NearbyBLEDevicesPopupView: View {
    @ObservedObject var nearbyStore: NearbyBLEDevicesStore
    let currentBinding: VehicleBLEBinding?
    let onBind: (VehicleBLEManager.NearbyDevice) -> Void
    let onClearBinding: () -> Void
    let onClose: () -> Void

    var body: some View {
        FloatingPopupCard(
            icon: "dot.radiowaves.left.and.right",
            iconColor: AppTheme.orange,
            title: "附近设备",
            subtitle: currentBinding == nil ? "可手动绑定附近候选设备；绑定后会立即检查可用性。" : "当前已有绑定；也可以改绑附近候选设备。",
            maxWidth: 332,
            contentScrollEnabled: false
        ) {
            ScrollView(.vertical, showsIndicators: nearbyStore.devices.count > 4) {
                VStack(alignment: .leading, spacing: 10) {
                    if nearbyStore.devices.isEmpty {
                        Text("扫描中暂无可展示候选；保持扫描后会逐步出现附近设备。")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(nearbyStore.devices) { device in
                            NearbyBLEDeviceRowView(
                                device: device,
                                isBound: currentBinding?.peripheralIdentifier == device.peripheralIdentifier,
                                onBind: { onBind(device) }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 320, alignment: .top)
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(title: "刷新列表", color: AppTheme.orange) {
                    nearbyStore.flush()
                }
                if currentBinding != nil {
                    FloatingPopupPrimaryButton(title: "取消绑定", color: AppTheme.red) {
                        onClearBinding()
                    }
                }
                FloatingPopupSecondaryButton(title: "关闭", textColor: .white) {
                    onClose()
                }
            }
        }
    }
}

private struct NearbyBLEDeviceRowView: View, Equatable {
    let device: VehicleBLEManager.NearbyDevice
    let isBound: Bool
    let onBind: () -> Void

    static func == (lhs: NearbyBLEDeviceRowView, rhs: NearbyBLEDeviceRowView) -> Bool {
        lhs.device == rhs.device && lhs.isBound == rhs.isBound
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if device.exactMatched {
                        Text("目标匹配")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.green))
                    }
                    if isBound {
                        Text("已绑定")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.accent))
                    }
                }
                Text(detailText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(isBound ? "改绑" : "绑定") {
                onBind()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(AppTheme.accent))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isBound ? AppTheme.accent.opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var detailText: String {
        let mac = device.manufacturerMac ?? "--"
        let scoreText = device.score.map(String.init) ?? "--"
        return "rssi=\(device.rssi) · score=\(scoreText) · mac=\(mac)"
    }
}
