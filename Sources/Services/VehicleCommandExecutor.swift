import Foundation

enum VehicleCommandExecutionState: Equatable {
    case feedbackOnly
    case planned
    case sent
    case completed
    case failed(String)
    case timedOut(String)
}

struct VehicleCommandTiming: Equatable {
    let requestBuildMillis: Int
    let httpRoundTripMillis: Int

    var summary: String {
        "build=\(requestBuildMillis)ms, http=\(httpRoundTripMillis)ms"
    }
}

struct VehicleCommandExecutionResult: Equatable {
    let command: VehicleCommand
    let state: VehicleCommandExecutionState
    let userMessage: String
    let shouldRefresh: Bool
    let refreshDelay: TimeInterval
    var timing: VehicleCommandTiming? = nil
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

protocol VehicleBLEControlling: AnyObject {
    var canUseBLEForVehicleControl: Bool { get }
    func sendCommandViaBLE(command: VehicleCommand, completion: @escaping (Result<Void, VehicleBLEManager.BLEControlError>) -> Void)
}

protocol VehicleBLEDoorLockControlling: VehicleBLEControlling {
    var canUseBLEForDoorLock: Bool { get }
    func sendDoorLockViaBLE(command: VehicleCommand, completion: @escaping (Result<Void, VehicleBLEManager.BLEControlError>) -> Void)
}

struct FeedbackOnlyTransport: VehicleCommandTransport {
    func execute(_ command: VehicleCommand, refresher: VehicleCommandRefreshing?) -> VehicleCommandExecutionResult {
        refresher?.refreshNow()
        return VehicleCommandExecutionResult(
            command: command,
            state: .feedbackOnly,
            userMessage: "操作已提交，请查看车辆状态。",
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
                userMessage: "控制请求已准备就绪",
                shouldRefresh: false,
                refreshDelay: 0
            )
        }
    }
}

struct BLEVehicleControlTransport: VehicleCommandAsyncTransport {
    weak var bleController: VehicleBLEControlling?

    init(bleController: VehicleBLEControlling?) {
        self.bleController = bleController
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

        guard command.kind.supportsBLEControl else {
            finish(VehicleCommandExecutionResult(command: command, state: .failed("当前 BLE transport 不支持该命令"), userMessage: "当前 BLE transport 不支持 \(command.title)", shouldRefresh: false, refreshDelay: 0))
            return
        }
        guard let bleController else {
            finish(VehicleCommandExecutionResult(command: command, state: .failed("缺少 BLE 控制器"), userMessage: "未配置 BLE 控制器", shouldRefresh: false, refreshDelay: 0))
            return
        }
        bleController.sendCommandViaBLE(command: command) { result in
            switch result {
            case .success:
                let message = "\(command.title) 已完成"
                finish(VehicleCommandExecutionResult(command: command, state: .completed, userMessage: message, shouldRefresh: false, refreshDelay: 0))
            case .failure(let error):
                let state: VehicleCommandExecutionState
                let message: String
                switch error {
                case .receiptTimeout:
                    state = .timedOut(error.localizedDescription)
                    message = "蓝牙控制等待回包超时。请检查蓝牙连接后重试"
                case .controlRejected(let detail):
                    state = .failed(error.localizedDescription)
                    message = "\(command.title)被车辆拒绝（\(detail)）"
                default:
                    state = .failed(error.localizedDescription)
                    message = error.localizedDescription + "。请检查蓝牙连接后重试"
                }
                finish(VehicleCommandExecutionResult(command: command, state: state, userMessage: message, shouldRefresh: false, refreshDelay: 0))
            }
        }
    }
}

struct BLEDoorLockTransport: VehicleCommandAsyncTransport {
    private let wrapped: BLEVehicleControlTransport

    init(bleController: VehicleBLEDoorLockControlling?) {
        self.wrapped = BLEVehicleControlTransport(bleController: bleController)
    }

    func executeAsync(
        _ command: VehicleCommand,
        refresher: VehicleCommandRefreshing?,
        completion: @escaping (VehicleCommandExecutionResult) -> Void
    ) {
        wrapped.executeAsync(command, refresher: refresher, completion: completion)
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
        let buildStart = Date()
        switch apiClient.makeVehicleControlRequestDraft(accessToken: accessToken, vin: vin, command: command) {
        case .failure(let error):
            let buildMillis = Int(Date().timeIntervalSince(buildStart) * 1000)
            finish(VehicleCommandExecutionResult(command: command, state: .failed(error.localizedDescription), userMessage: error.localizedDescription, shouldRefresh: false, refreshDelay: 0, timing: VehicleCommandTiming(requestBuildMillis: buildMillis, httpRoundTripMillis: 0)))
        case .success(let draft):
            let buildMillis = Int(Date().timeIntervalSince(buildStart) * 1000)
            let requestSummary = draft.redactedRequestSummary
            let httpStart = Date()
            apiClient.sendVehicleControlRequestDraft(draft) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        let message: String
                        if command.kind == .remoteStart {
                            message = "启动授权已发送。请在约 30 秒内解锁上车，踩下刹车仪表亮Ready。"
                        } else if command.kind == .remoteStop {
                            message = "熄火指令已发送，等待车辆状态更新。"
                        } else {
                            message = "\(command.title) 指令已发送，等待车辆状态更新。"
                        }
                        let timing = VehicleCommandTiming(requestBuildMillis: buildMillis, httpRoundTripMillis: Int(Date().timeIntervalSince(httpStart) * 1000))
                        completion(VehicleCommandExecutionResult(command: command, state: .sent, userMessage: message, shouldRefresh: true, refreshDelay: 0, timing: timing))
                        // 上电/熄火后加快收敛：1.5s + 4s 各刷一次车况
                        let refreshDelays: [TimeInterval] = (command.kind == .remoteStart || command.kind == .remoteStop) ? [1.5, 4.0] : [2.1]
                        for delay in refreshDelays {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                refresher?.refreshNow()
                            }
                        }
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
                    let timing = VehicleCommandTiming(requestBuildMillis: buildMillis, httpRoundTripMillis: Int(Date().timeIntervalSince(httpStart) * 1000))
                    finish(VehicleCommandExecutionResult(command: command, state: state, userMessage: message, shouldRefresh: false, refreshDelay: 0, timing: timing))
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

extension MQTTVehicleStateStore: VehicleCommandRefreshing, VehicleBLEDoorLockControlling {}
extension VehicleCredentialsStore: VehicleCommandCredentialProviding {}
