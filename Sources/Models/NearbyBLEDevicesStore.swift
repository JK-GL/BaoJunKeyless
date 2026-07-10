import Foundation
import Combine

final class NearbyBLEDevicesStore: ObservableObject {
    /// 对外展示列表：只在结构变化或手动/定时刷新时更新。
    @Published private(set) var devices: [VehicleBLEManager.NearbyDevice] = []
    /// 仅数量变化时更新，给入口角标用，避免拖累列表弹窗。
    @Published private(set) var count: Int = 0

    private var buffer: [String: VehicleBLEManager.NearbyDevice] = [:]
    private var flushWorkItem: DispatchWorkItem?
    private let flushInterval: TimeInterval = 0.8

    func reset() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        buffer = [:]
        if !devices.isEmpty {
            devices = []
        }
        if count != 0 {
            count = 0
        }
    }

    func ingest(_ device: VehicleBLEManager.NearbyDevice) {
        buffer[device.id] = device
        guard flushWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.flush(forcePublishDevices: false)
        }
        flushWorkItem = work
        // 比之前更接近系统“附近”节奏：批量合并，降低主线程发布频率
        DispatchQueue.main.asyncAfter(deadline: .now() + flushInterval, execute: work)
    }

    func flush() {
        flush(forcePublishDevices: true)
    }

    /// - Parameter forcePublishDevices: true 表示弹窗手动刷新/打开时强制同步列表；
    ///   false 表示后台扫描时只更新角标数量，避免弹窗打开过程中频繁重绘列表。
    private func flush(forcePublishDevices: Bool) {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        let now = Date()
        let next = Array(
            buffer.values
                .filter { now.timeIntervalSince($0.lastSeenAt) <= 30 }
                .sorted {
                    if $0.exactMatched != $1.exactMatched { return $0.exactMatched && !$1.exactMatched }
                    if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
                    return $0.displayName < $1.displayName
                }
        )

        if count != next.count {
            count = next.count
        }

        if forcePublishDevices {
            if devices != next {
                devices = next
            }
            return
        }

        // 后台扫描：仅当列表结构变化时才发布 devices，普通 RSSI 抖动不刷 UI
        guard meaningfullyChanged(from: devices, to: next) else { return }
        devices = next
    }

    private func meaningfullyChanged(
        from old: [VehicleBLEManager.NearbyDevice],
        to new: [VehicleBLEManager.NearbyDevice]
    ) -> Bool {
        guard old.count == new.count else { return true }
        for (lhs, rhs) in zip(old, new) {
            if lhs.id != rhs.id { return true }
            if lhs.exactMatched != rhs.exactMatched { return true }
            if lhs.manufacturerMac != rhs.manufacturerMac { return true }
            // score 小幅波动不刷；只有跨档才算结构变化
            let oldScore = lhs.score ?? Int.min
            let newScore = rhs.score ?? Int.min
            if abs(oldScore - newScore) >= 8 { return true }
        }
        return false
    }
}
