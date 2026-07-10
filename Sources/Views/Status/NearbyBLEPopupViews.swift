import SwiftUI

struct NearbyBLEDevicesLaunchButton: View {
    @ObservedObject var nearbyStore: NearbyBLEDevicesStore
    let action: () -> Void

    var body: some View {
        // 只依赖 count，避免 devices 数组更新时重绘整颗按钮树的重布局成本
        NearbyBLEDevicesLaunchButtonContent(
            count: nearbyStore.count,
            action: action
        )
    }
}

private struct NearbyBLEDevicesLaunchButtonContent: View, Equatable {
    let count: Int
    let action: () -> Void

    static func == (lhs: NearbyBLEDevicesLaunchButtonContent, rhs: NearbyBLEDevicesLaunchButtonContent) -> Bool {
        lhs.count == rhs.count
    }

    var body: some View {
        PopupActionGridButton(
            title: "附近设备",
            icon: "dot.radiowaves.left.and.right",
            tint: AppTheme.orange,
            badgeText: count > 0 ? "\(count)" : nil,
            action: action
        )
    }
}

struct NearbyBLEDevicesPopupView: View {
    let nearbyStore: NearbyBLEDevicesStore
    let currentBinding: VehicleBLEBinding?
    let onBind: (VehicleBLEManager.NearbyDevice) -> Void
    let onClearBinding: () -> Void
    let onClose: () -> Void

    /// 打开后用快照展示，不直接订阅 @Published devices，避免扫描广播牵动整窗重绘
    @State private var snapshotDevices: [VehicleBLEManager.NearbyDevice] = []
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        FloatingPopupCard(
            icon: "dot.radiowaves.left.and.right",
            iconColor: AppTheme.orange,
            title: "附近设备",
            subtitle: currentBinding == nil
                ? "打开后按快照展示；列表约每秒刷新，避免扫描卡顿。"
                : "当前已有绑定；也可改绑附近候选设备。",
            maxWidth: 332,
            fixedContentHeight: 320,
            contentScrollEnabled: false
        ) {
            ScrollView(.vertical, showsIndicators: snapshotDevices.count > 5) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if snapshotDevices.isEmpty {
                        Text("扫描中暂无可展示候选；保持扫描后点“刷新列表”。")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(snapshotDevices) { device in
                            NearbyBLEDeviceRowView(
                                id: device.id,
                                displayName: device.displayName,
                                rssi: device.rssi,
                                scoreText: device.score.map(String.init) ?? "--",
                                mac: device.manufacturerMac ?? "--",
                                exactMatched: device.exactMatched,
                                isBound: currentBinding?.peripheralIdentifier == device.peripheralIdentifier,
                                onBind: { onBind(device) }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320, alignment: .top)
        } actions: {
            VStack(spacing: 8) {
                FloatingPopupPrimaryButton(title: "刷新列表", color: AppTheme.orange) {
                    nearbyStore.flush()
                    snapshotDevices = nearbyStore.devices
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
        .onAppear {
            nearbyStore.flush()
            snapshotDevices = nearbyStore.devices
            startAutoRefresh()
        }
        .onDisappear {
            autoRefreshTask?.cancel()
            autoRefreshTask = nil
        }
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                // 定时从 buffer 拉快照；不直接绑定 @Published devices，避免高频 invalidation
                nearbyStore.flush()
                let next = nearbyStore.devices
                if next != snapshotDevices {
                    snapshotDevices = next
                }
            }
        }
    }
}

/// 行视图只比较展示字段，避免闭包破坏 diff。
private struct NearbyBLEDeviceRowView: View, Equatable {
    let id: String
    let displayName: String
    let rssi: Int
    let scoreText: String
    let mac: String
    let exactMatched: Bool
    let isBound: Bool
    let onBind: () -> Void

    static func == (lhs: NearbyBLEDeviceRowView, rhs: NearbyBLEDeviceRowView) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.rssi == rhs.rssi
            && lhs.scoreText == rhs.scoreText
            && lhs.mac == rhs.mac
            && lhs.exactMatched == rhs.exactMatched
            && lhs.isBound == rhs.isBound
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if exactMatched {
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
                Text("rssi=\(rssi) · score=\(scoreText) · mac=\(mac)")
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
            .buttonStyle(.plain)
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
}
