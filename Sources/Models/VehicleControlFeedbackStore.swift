import Foundation
import Combine

final class VehicleControlFeedbackStore: ObservableObject {
    static let shared = VehicleControlFeedbackStore()

    @Published var latestBLEControlReceipt: VehicleBLEManager.BLEControlReceipt?
    @Published var latestControlResult: VehicleControlMQTTResult?

    func setBLEControlReceipt(_ receipt: VehicleBLEManager.BLEControlReceipt?) {
        latestBLEControlReceipt = receipt
    }

    func setControlResult(_ result: VehicleControlMQTTResult?) {
        latestControlResult = result
    }

    func clear() {
        latestBLEControlReceipt = nil
        latestControlResult = nil
    }
}
