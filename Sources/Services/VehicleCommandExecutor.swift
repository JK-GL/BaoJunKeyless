import Foundation

enum VehicleCommandExecutionState: Equatable {
    case feedbackOnly
    case sent
    case completed
    case failed(String)
}

struct VehicleCommandExecutionResult: Equatable {
    let command: VehicleCommand
    let state: VehicleCommandExecutionState
    let userMessage: String
    let shouldRefresh: Bool
    let refreshDelay: TimeInterval
}

protocol VehicleCommandRefreshing: AnyObject {
    func refreshNow()
}

struct VehicleCommandExecutor {
    static func executeFeedbackOnly(
        _ command: VehicleCommand,
        refresher: VehicleCommandRefreshing?
    ) -> VehicleCommandExecutionResult {
        refresher?.refreshNow()
        return VehicleCommandExecutionResult(
            command: command,
            state: .feedbackOnly,
            userMessage: "已收到点击反馈，状态以车辆真实回报为准",
            shouldRefresh: true,
            refreshDelay: 0
        )
    }
}

extension MQTTVehicleStateStore: VehicleCommandRefreshing {}
