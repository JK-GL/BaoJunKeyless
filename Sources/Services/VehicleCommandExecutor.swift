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
    /// HTTP 请求发出前登记期望车况，避免 status MQTT 比 HTTP 回调更早到达时漏确认。
    func beginControlStateConfirmation(_ command: VehicleCommand)
    /// HTTP 请求失败时撤销尚未被真实车况确认的期望态。
    func cancelControlStateConfirmation(_ command: VehicleCommand)
    /// HTTP 车控接口返回成功（指令已受理）后，立刻回写可预期的本地状态，避免只等轮询/MQTT。
    /// 默认空实现；MQTTVehicleStateStore 覆盖。
    func applyAcceptedHTTPControlIfPossible(_ command: VehicleCommand)
}

extension VehicleCommandRefreshing {
    func beginControlStateConfirmation(_ command: VehicleCommand) {}
    func cancelControlStateConfirmation(_ command: VehicleCommand) {}
    func applyAcceptedHTTPControlIfPossible(_ command: VehicleCommand) {}
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
            // executeAsync 由前台主线程发起；status MQTT 可能比 HTTP completion 更早抵达，
            // 所以必须在请求真正发出前同步挂起期望态。
            refresher?.beginControlStateConfirmation(command)
            apiClient.sendVehicleControlRequestDraft(draft) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        // HTTP 受理成功：先本地即时回写可预期状态（锁/电源/空调/车窗），再弹结果与补刷。
                        refresher?.applyAcceptedHTTPControlIfPossible(command)

                        // 用户可见结果文案：只说做了什么，不暴露 MQTT/HTTP/确认链路。
                        let message: String
                        switch command.kind {
                        case .remoteStart:
                            message = "已启动。请在约 30 秒内解锁上车，踩下刹车后仪表亮 Ready（已启动≠Ready）。"
                        case .remoteStop:
                            message = "车辆已熄火"
                        case .acOn:
                            message = "空调已开启"
                        case .acOff:
                            message = "空调已关闭"
                        case .setTemperature:
                            if let temp = command.requestedTemperature.map({ Int($0.rounded()) }) {
                                message = "温度已设为 \(temp)°C"
                            } else {
                                message = "温度已设定"
                            }
                        case .quickCool:
                            message = "快速降温已开启"
                        case .lock:
                            message = "车门已上锁"
                        case .unlock:
                            message = "车门已解锁"
                        case .openWindows:
                            message = "车窗已打开"
                        case .closeWindows:
                            message = "车窗已关闭"
                        case .findCar:
                            message = "寻车指令已发送"
                        }
                        let timing = VehicleCommandTiming(requestBuildMillis: buildMillis, httpRoundTripMillis: Int(Date().timeIntervalSince(httpStart) * 1000))
                        completion(VehicleCommandExecutionResult(command: command, state: .sent, userMessage: message, shouldRefresh: true, refreshDelay: 0, timing: timing))
                        // 本地已即时回写；仍用短间隔 HTTP 权威收敛（防车端拒绝/半成功）。
                        // - 锁/解：0.4s 起补刷（不再干等 2.1s）
                        // - 上电/熄火：1.5s + 4s
                        // - 空调/设温/车窗/寻车：0.3s 起连续补刷
                        let refreshDelays: [TimeInterval]
                        switch command.kind {
                        case .remoteStart, .remoteStop:
                            refreshDelays = [1.5, 4.0]
                        case .lock, .unlock:
                            refreshDelays = [0.4, 1.2, 2.5, 4.5]
                        case .acOn, .acOff, .setTemperature, .quickCool, .openWindows, .closeWindows, .findCar:
                            refreshDelays = [0.3, 1.2, 2.5, 4.5]
                        default:
                            refreshDelays = [0.5, 2.0]
                        }
                        for delay in refreshDelays {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                refresher?.refreshNow()
                            }
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        refresher?.cancelControlStateConfirmation(command)
                    }
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
