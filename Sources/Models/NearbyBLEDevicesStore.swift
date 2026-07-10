import Foundation
import Combine

final class NearbyBLEDevicesStore: ObservableObject {
    @Published private(set) var devices: [VehicleBLEManager.NearbyDevice] = []

    private var buffer: [String: VehicleBLEManager.NearbyDevice] = [:]
    private var flushWorkItem: DispatchWorkItem?

    var count: Int { devices.count }

    func reset() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        buffer = [:]
        devices = []
    }

    func ingest(_ device: VehicleBLEManager.NearbyDevice) {
        buffer[device.id] = device
        guard flushWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        flushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func flush() {
        flushWorkItem?.cancel()
        flushWorkItem = nil

        let now = Date()
        let next = Array(
            buffer.values
                .filter { now.timeIntervalSince($0.lastSeenAt) <= 30 }
                .sorted {
                    if $0.exactMatched != $1.exactMatched { return $0.exactMatched && !$1.exactMatched }
                    return $0.rssi > $1.rssi
                }
        )

        guard meaningfullyChanged(from: devices, to: next) else { return }
        devices = next
    }

    private func meaningfullyChanged(from old: [VehicleBLEManager.NearbyDevice], to new: [VehicleBLEManager.NearbyDevice]) -> Bool {
        guard old.count == new.count else { return true }
        for (lhs, rhs) in zip(old, new) {
            if lhs.id != rhs.id { return true }
            if lhs.exactMatched != rhs.exactMatched { return true }
            if lhs.manufacturerMac != rhs.manufacturerMac { return true }
            if lhs.score != rhs.score { return true }
        }
        return false
    }
}
