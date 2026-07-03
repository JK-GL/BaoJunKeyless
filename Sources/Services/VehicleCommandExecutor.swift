import Foundation

enum VehicleCommandExecutionState: Equatable {
    case feedbackOnly
    case planned
    case sent
    case completed
    case failed(String)
    case timedOut(String)
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

protocol VehicleCommandAsyncTransport {
    func executeAsync(
        _ command: VehicleCommand,
        refresher: VehicleCommandRefreshing?,
        completion: @escaping (VehicleCommandExecutionResult) -> Void
    )
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

struct HTTPControlTransport: VehicleCommandAsyncTransport {
    let apiClient: SGMWApiClient
    weak var credentials: VehicleCommandCredentialProviding?

    init(apiClient: SGMWApiClient = .shared, credentials: VehicleCommandCredentialProviding?) {
        self.apiClient = apiClient
        self.credentials = credentials
    }

    func executeAsync(
        _ command: VehicleCommand,
        refresher: VehicleCommandRefreshing?,
        completion: @escaping (VehicleCommandExecutionResult) -> Void
    ) {
        func finish(_ result: VehicleCommandExecutionResult) {
            DispatchQueue.main.async {
                completion(result)
            }
        }

        guard let credentials else {
            finish(VehicleCommandExecutionResult(command: command, state: .failed("缺少车辆凭证提供者"), userMessage: "未配置车辆凭证，无法发送控制请求", shouldRefresh: false, refreshDelay: 0))
            return
        }
        let accessToken = credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let vin = credentials.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty, !vin.isEmpty else {
            finish(VehicleCommandExecutionResult(command: command, state: .failed("缺少 accessToken 或 VIN"), userMessage: "缺少 accessToken 或 VIN，无法发送控制请求", shouldRefresh: false, refreshDelay: 0))
            return
        }
        switch apiClient.makeVehicleControlRequestDraft(accessToken: accessToken, vin: vin, command: command) {
        case .failure(let error):
            finish(VehicleCommandExecutionResult(command: command, state: .failed(error.localizedDescription), userMessage: error.localizedDescription, shouldRefresh: false, refreshDelay: 0))
        case .success(let draft):
            let requestSummary = draft.redactedRequestSummary
            apiClient.sendVehicleControlRequestDraft(draft) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        refresher?.refreshNow()
                        let message: String
                        if command.kind == .remoteStart {
                            message = "远程启动授权请求已发送：\(requestSummary)，后续启动仍以车辆 / BLE 回报为准"
                        } else {
                            message = "控制请求已发送：\(requestSummary)，等待车辆真实回报"
                        }
                        completion(VehicleCommandExecutionResult(command: command, state: .sent, userMessage: message, shouldRefresh: true, refreshDelay: 0))
                    }
                case .failure(let error):
                    let state: VehicleCommandExecutionState
                    if case .network(let underlying) = error,
                       let urlError = underlying as? URLError,
                       urlError.code == .timedOut {
                        state = .timedOut(error.localizedDescription)
                    } else {
                        state = .failed(error.localizedDescription)
                    }
                    let message = "\(requestSummary)；\(error.localizedDescription)"
                    finish(VehicleCommandExecutionResult(command: command, state: state, userMessage: message, shouldRefresh: false, refreshDelay: 0))
                }
            }
        }
    }
}

private extension SGMWApiClient.VehicleControlRequestDraft {
    var redactedRequestSummary: String {
        let endpoint = plan.endpointCandidates.first ?? url.lastPathComponent
        let bodySummary = body
            .filter { $0.key.lowercased() != "vin" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return bodySummary.isEmpty ? "POST \(endpoint)" : "POST \(endpoint) body={\(bodySummary)}"
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

    static func executeAsync(
        _ command: VehicleCommand,
        transport: VehicleCommandAsyncTransport,
        refresher: VehicleCommandRefreshing?,
        completion: @escaping (VehicleCommandExecutionResult) -> Void
    ) {
        transport.executeAsync(command, refresher: refresher, completion: completion)
    }
}

extension MQTTVehicleStateStore: VehicleCommandRefreshing {}
extension VehicleCredentialsStore: VehicleCommandCredentialProviding {}
