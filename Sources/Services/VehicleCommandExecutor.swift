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

protocol VehicleCommandCredentialProviding: AnyObject {
    var accessToken: String { get }
    var vin: String { get }
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
    weak var credentials: VehicleCommandCredentialProviding?

    init(apiClient: SGMWApiClient = .shared, credentials: VehicleCommandCredentialProviding?) {
        self.apiClient = apiClient
        self.credentials = credentials
    }

    func execute(_ command: VehicleCommand, refresher: VehicleCommandRefreshing?) -> VehicleCommandExecutionResult {
        guard let credentials else {
            return VehicleCommandExecutionResult(
                command: command,
                state: .failed("缺少车辆凭证提供者"),
                userMessage: "未配置车辆凭证，无法生成控制请求",
                shouldRefresh: false,
                refreshDelay: 0
            )
        }
        guard !credentials.accessToken.isEmpty, !credentials.vin.isEmpty else {
            return VehicleCommandExecutionResult(
                command: command,
                state: .failed("缺少 accessToken 或 VIN"),
                userMessage: "缺少 accessToken 或 VIN，无法生成控制请求",
                shouldRefresh: false,
                refreshDelay: 0
            )
        }
        switch apiClient.makeVehicleControlRequestDraft(accessToken: credentials.accessToken, vin: credentials.vin, command: command) {
        case .failure(let error):
            return VehicleCommandExecutionResult(
                command: command,
                state: .failed(error.localizedDescription),
                userMessage: error.localizedDescription,
                shouldRefresh: false,
                refreshDelay: 0
            )
        case .success(let draft):
            return VehicleCommandExecutionResult(
                command: command,
                state: .planned,
                userMessage: "已生成控制草稿：\(draft.plan.endpointCandidates.first ?? draft.url.absoluteString)",
                shouldRefresh: false,
                refreshDelay: 0
            )
        }
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
extension VehicleCredentialsStore: VehicleCommandCredentialProviding {}
