import Foundation
import Combine

enum VehicleControlStateConfirmationSource: String, Equatable {
    case mqttStatus = "MQTT车况"
    case httpStatus = "HTTP车况"
    /// 已确认离线时，BLE 控制回包是唯一可用的现场确认。
    case ble = "蓝牙"
    case timeout = "状态未确认"

    var title: String { rawValue }
}

/// HTTP 控制受理后，由真实车况（MQTT status / HTTP 全量）产生的确认结果。
/// `/vehicle/control` PB 是附加诊断，不能替代此结果。
struct VehicleControlStateConfirmation: Equatable, Identifiable {
    let id = UUID()
    let commandTitle: String
    let expectedDescription: String
    let observedDescription: String
    let source: VehicleControlStateConfirmationSource
    let elapsedMillis: Int

    var isConfirmed: Bool { source != .timeout }
}

final class VehicleControlFeedbackStore: ObservableObject {
    static let shared = VehicleControlFeedbackStore()

    @Published var latestBLEControlReceipt: VehicleBLEManager.BLEControlReceipt?
    /// 可选 `/vehicle/control` Protobuf 回执，仅供诊断。
    @Published var latestControlResult: VehicleControlMQTTResult?
    /// 主确认链：MQTT status 或 HTTP 车况命中 HTTP 控制的期望态。
    @Published var latestStateConfirmation: VehicleControlStateConfirmation?

    func setBLEControlReceipt(_ receipt: VehicleBLEManager.BLEControlReceipt?) {
        latestBLEControlReceipt = receipt
    }

    func setControlResult(_ result: VehicleControlMQTTResult?) {
        latestControlResult = result
    }

    func setStateConfirmation(_ confirmation: VehicleControlStateConfirmation?) {
        latestStateConfirmation = confirmation
    }

    func clear() {
        latestBLEControlReceipt = nil
        latestControlResult = nil
        latestStateConfirmation = nil
    }
}
