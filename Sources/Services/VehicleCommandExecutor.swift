import Foundation

enum VehicleCommandExecutionState: Equatable {
    case feedbackOnly
    case planned
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

protocol VehicleCommandTransport {
    func execute(_ command: VehicleCommand, refresher: VehicleCommandRefreshing?) -> VehicleCommandExecutionResult
}

struct FeedbackOnlyTransport: VehicleCommandTransport {
    func execute(_ command: VehicleCommand, refresher: VehicleCommandRefreshing?) -> VehicleCommandExecutionResult {
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

struct PlaceholderControlTransport: VehicleCommandTransport {
    let apiClient: SGMWApiClient

    init(apiClient: SGMWApiClient = .shared) {
        self.apiClient = apiClient
    }

    func execute(_ command: VehicleCommand, refresher: VehicleCommandRefreshing?) -> VehicleCommandExecutionResult {
        let plan = apiClient.makeVehicleControlRequestPlan(for: command)
        return VehicleCommandExecutionResult(
            command: command,
            state: .planned,
            userMessage: "已生成控制计划：\(plan.endpointCandidates.first ?? "待确认接口")",
            shouldRefresh: false,
            refreshDelay: 0
        )
    }
}

struct VehicleCommandExecutor {
    static func executeFeedbackOnly(
        _ command: VehicleCommand,
        refresher: VehicleCommandRefreshing?
    ) -> VehicleCommandExecutionResult {
        FeedbackOnlyTransport().execute(command, refresher: refresher)
    }

    static func execute(
        _ command: VehicleCommand,
        transport: VehicleCommandTransport,
        refresher: VehicleCommandRefreshing?
    ) -> VehicleCommandExecutionResult {
        transport.execute(command, refresher: refresher)
    }
}

extension MQTTVehicleStateStore: VehicleCommandRefreshing {}
