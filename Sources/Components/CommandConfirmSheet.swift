import SwiftUI

// MARK: - 执行结果
enum CommandResult {
    case success
    case failure
    case timeout

    var color: Color {
        switch self {
        case .success:  return AppTheme.green
        case .failure:  return AppTheme.red
        case .timeout:  return AppTheme.orange
        }
    }

    var title: String {
        switch self {
        case .success:  return "已完成"
        case .failure:  return "执行失败"
        case .timeout:  return "连接超时"
        }
    }

    var message: String {
        switch self {
        case .success:  return "操作已完成"
        case .failure:  return "指令未成功，请稍后重试"
        case .timeout:  return "车辆未响应，请检查网络后重试"
        }
    }
}

// MARK: - 车控指令类型
enum CommandAction: String, Identifiable, Equatable {
    case lockUnlock     // 解锁/锁车（状态联动）
    case remoteStart    // 远程启动
    case findCar        // 寻车
    case acToggle       // 空调开关（状态联动）
    case windowToggle   // 车窗开关（状态联动）
    case quickCool      // 快速降温

    var id: String { rawValue }

    /// 执行失败按钮标题
    func failureTitle(result: CommandResult) -> String {
        switch result {
        case .failure:  return "执行失败"
        case .timeout:  return "连接超时"
        default:        return "执行失败"
        }
    }

    /// 根据车辆状态动态返回图标
    func icon(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == false ? "lock.open.fill" : "lock.fill"
        case .remoteStart:
            return (state.power.isPoweredOn) ? "power.circle.fill" : "power"
        case .findCar:
            return "location.fill"
        case .acToggle:
            return "snowflake"
        case .windowToggle:
            return "rectangle.split.2x2.fill"
        case .quickCool:
            return "snowflake"
        }
    }

    func label(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == false ? "已开锁" : "锁车"
        case .remoteStart:
            return state.power == .unknown ? "电源未知" : (state.power.isPoweredOn ? state.power.title : "熄火")
        case .findCar:
            return "寻车"
        case .acToggle:
            return state.acOn == true ? "已开空调" : "空调"
        case .windowToggle:
            return state.windowsClosed == false ? "已开窗" : "车窗"
        case .quickCool:
            return "快冷"
        }
    }

    /// 主题色
    var color: Color {
        switch self {
        case .lockUnlock:    return AppTheme.green
        case .remoteStart:   return AppTheme.orange
        case .findCar:       return AppTheme.purple
        case .acToggle:      return AppTheme.accent
        case .windowToggle:  return Color(red: 0.22, green: 0.74, blue: 1.0)
        case .quickCool:     return Color(red: 0.16, green: 0.88, blue: 0.96)
        }
    }

    func resolvedColor(state: VehicleState) -> Color {
        switch self {
        case .lockUnlock:
            return state.locked == false ? AppTheme.red : AppTheme.green
        case .remoteStart:
            return (state.power.isPoweredOn) ? AppTheme.green : Color(red: 0.55, green: 0.58, blue: 0.62)
        case .acToggle:
            return state.acOn == true ? AppTheme.accent : Color(red: 0.55, green: 0.58, blue: 0.62)
        case .windowToggle:
            return state.windowsClosed == false ? Color(red: 0.22, green: 0.74, blue: 1.0) : Color(red: 0.55, green: 0.58, blue: 0.62)
        default:
            return color
        }
    }

    /// 确认弹窗标题（官方风格）
    func confirmTitle(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == false ? "锁车" : "解锁车辆"
        case .remoteStart:   return (state.power.isPoweredOn) ? "远程熄火" : "远程启动"
        case .findCar:       return "寻车"
        case .acToggle:
            return state.acOn == true ? "关闭空调" : "开启空调"
        case .windowToggle:
            return state.windowsClosed == false ? "关闭车窗" : "打开车窗"
        case .quickCool:     return "快速降温"
        }
    }

    /// 确认弹窗副标题（官方风格）
    func confirmMessage(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == false ? "确认后将锁止车门，请确保车内无人滞留。" : "确认后将解锁车门，便于您上车。"
        case .remoteStart:
            return state.power.isPoweredOn
                ? "确认后将关闭车辆电源。优先使用近场蓝牙，不可用时自动改用网络。"
                : "确认后将下发启动授权。请在约 30 秒内解锁上车，踩下刹车仪表亮Ready。"
        case .findCar:
            return "确认后车辆将闪灯并鸣笛，便于您快速定位。"
        case .acToggle:
            return state.acOn == true ? "确认后将关闭空调。" : "确认后将开启空调，可调节设定温度。"
        case .windowToggle:
            return state.windowsClosed == false ? "确认后将关闭全部车窗。" : "确认后将打开全部车窗。"
        case .quickCool:
            return "确认后将按设定温度快速降温，可调节温度与时长。"
        }
    }

    /// 是否需要温度滑块
    var needsTemperatureSlider: Bool {
        self == .acToggle || self == .quickCool
    }

    /// 是否需要持续时间滑块
    var needsDurationSlider: Bool {
        self == .quickCool
    }
}

// MARK: - 车控指令确认弹窗（居中卡片）
struct CommandConfirmPopup: View {
    let action: CommandAction
    let vehicleState: VehicleState
    @Binding var isPresented: Bool
    let onConfirm: (CommandAction, Double?, Int?, @escaping (VehicleCommandExecutionResult) -> Void) -> Void

    @State private var temperature: Double
    @State private var durationMinutes: Double
    @State private var isExecuting = false
    @State private var commandResult: CommandResult? = nil
    @State private var resultMessage: String? = nil
    @State private var resultButtonTitle: String? = nil

    init(
        action: CommandAction,
        vehicleState: VehicleState,
        isPresented: Binding<Bool>,
        onConfirm: @escaping (CommandAction, Double?, Int?, @escaping (VehicleCommandExecutionResult) -> Void) -> Void
    ) {
        self.action = action
        self.vehicleState = vehicleState
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        let initialTemperature: Int
        if action == .quickCool {
            initialTemperature = 17
        } else {
            initialTemperature = Int(vehicleState.acTemperature ?? 22)
        }
        self._temperature = State(initialValue: Double(max(17, min(33, initialTemperature))))
        self._durationMinutes = State(initialValue: 10)
    }

    /// 始终显示真实状态源传入的车辆状态，点击反馈不再模拟覆盖。
    private var displayState: VehicleState {
        vehicleState
    }

    private var accentColor: Color {
        action.resolvedColor(state: displayState)
    }

    private var resultSubtitle: String {
        if let result = commandResult {
            return resultMessage ?? result.message
        }
        return action.confirmMessage(state: vehicleState)
    }

    private var resultIcon: String {
        if let result = commandResult {
            switch result {
            case .success:  return "checkmark.circle.fill"
            case .failure:  return "xmark.circle.fill"
            case .timeout:  return "wifi.slash"
            }
        }
        return action.icon(state: displayState)
    }

    private var resultColor: Color {
        if let result = commandResult {
            return result.color
        }
        return accentColor
    }

    private var commandTitle: String {
        action.asVehicleCommand(
            state: vehicleState,
            temperature: action.needsTemperatureSlider ? temperature : nil,
            durationMinutes: action.needsDurationSlider ? Int(durationMinutes) : nil,
            source: .quickAction
        ).title
    }

    var body: some View {
        FloatingPopupCard(
            icon: resultIcon,
            iconColor: resultColor,
            title: commandTitle,
            subtitle: resultSubtitle,
            contentScrollEnabled: false
        ) {
            VStack(spacing: 12) {
                PopupStatusSummaryView(items: statusItemsForCurrentAction)

                if action.needsTemperatureSlider && commandResult == nil {
                    PopupTemperatureSlider(
                        title: "设定温度",
                        temperature: $temperature,
                        range: 17...33,
                        tint: accentColor
                    )
                }

                if action.needsDurationSlider && commandResult == nil {
                    PopupDurationSlider(
                        title: "持续时间",
                        durationMinutes: $durationMinutes,
                        range: 5...20,
                        tint: accentColor
                    )
                }
            }
        } actions: {
            if let result = commandResult {
                // 执行后：结果按钮（disabled，用对应颜色背景）
                FloatingPopupPrimaryButton(
                    title: resultButtonTitle ?? result.title,
                    color: result.color,
                    isLoading: false,
                    isDisabled: true,
                    disabledBackgroundColor: result.color,
                    action: {}
                )
                .transition(PopupMotion.transition)
            } else if isExecuting {
                // 执行中：仅显示执行按钮，隐藏取消
                FloatingPopupPrimaryButton(
                    title: "执行中…",
                    color: accentColor,
                    isLoading: true,
                    isDisabled: true,
                    action: {}
                )
                .transition(PopupMotion.transition)
            } else {
                // 执行前：确认 + 取消
                VStack(spacing: 8) {
                    FloatingPopupPrimaryButton(
                        title: action.confirmTitle(state: vehicleState),
                        color: accentColor,
                        isLoading: false,
                        isDisabled: false,
                        action: executeCommand
                    )

                    FloatingPopupSecondaryButton(
                        title: "取消",
                        textColor: Color.white.opacity(0.6)
                    ) {
                        withAnimation(PopupMotion.dismissEase) { isPresented = false }
                    }
                }
                .transition(PopupMotion.transition)
            }
        }
        .animation(PopupMotion.contentEase, value: isExecuting)
        .animation(PopupMotion.contentEase, value: commandResult != nil)
    }

    private var statusItemsForCurrentAction: [PopupStatusItem] {
        let state = displayState
        switch action {
        case .lockUnlock:
            return [
                PopupStatusItem(icon: state.locked == false ? "lock.open.fill" : "lock.fill",
                                label: "车锁", value: state.locked == false ? "未锁" : "已锁",
                                color: state.locked == false ? AppTheme.red : AppTheme.green),
                PopupStatusItem(icon: "gearshape.fill", label: "档位",
                                value: state.gear.title, color: AppTheme.accent),
                PopupStatusItem(icon: "car.fill", label: "车门",
                                value: state.doorsClosed == false ? "未关" : "全关",
                                color: state.doorsClosed == false ? AppTheme.orange : AppTheme.green)
            ]
        case .remoteStart:
            let startStatusText: String
            let startStatusColor: Color
            startStatusText = state.power.remoteStartStatusTitle
            switch state.power {
            case .on, .ready:
                startStatusColor = AppTheme.green
            case .acc, .off, .unknown:
                startStatusColor = AppTheme.orange
            }
            return [
                PopupStatusItem(icon: "key.fill", label: "电源",
                                value: state.power.title, color: AppTheme.orange),
                PopupStatusItem(icon: "dot.radiowaves.left.and.right", label: "状态",
                                value: startStatusText, color: startStatusColor),
                PopupStatusItem(icon: "gearshape.fill", label: "档位",
                                value: state.gear.title, color: AppTheme.accent)
            ]
        case .findCar:
            return []
        case .acToggle:
            return [
                PopupStatusItem(icon: state.acOn == true ? "thermometer" : "snowflake",
                                label: "空调",
                                value: state.acOn == true ? "已开" : "已关",
                                color: state.acOn == true ? AppTheme.green : AppTheme.accent),
                PopupStatusItem(icon: "thermometer", label: "设定温度",
                                value: "\(Int(temperature))°C", color: AppTheme.accent)
            ]
        case .windowToggle:
            return [
                PopupStatusItem(icon: "rectangle.split.2x2.fill",
                                label: "车窗",
                                value: state.windowsClosed == false ? "未关" : "已关",
                                color: state.windowsClosed == false ? AppTheme.orange : AppTheme.green),
                PopupStatusItem(icon: "car.fill", label: "车门",
                                value: state.doorsClosed == false ? "未关" : "全关",
                                color: state.doorsClosed == false ? AppTheme.orange : AppTheme.green)
            ]
        case .quickCool:
            return [
                PopupStatusItem(icon: "thermometer", label: "设定温度",
                                value: "\(Int(temperature))°C", color: AppTheme.accent),
                PopupStatusItem(icon: "snowflake", label: "风量",
                                value: "7", color: AppTheme.accent),
                PopupStatusItem(icon: "timer", label: "持续时间",
                                value: "\(Int(durationMinutes)) 分钟", color: AppTheme.accent)
            ]
        }
    }

    private func executeCommand() {
        guard !isExecuting else { return }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        isExecuting = true
        commandResult = nil
        resultMessage = nil
        resultButtonTitle = nil

        let temperatureToUse = temperature
        let durationToUse = Int(durationMinutes)
        let label = commandTitle
        let temperatureDetail = action.needsTemperatureSlider ? " \(Int(temperatureToUse))°C" : ""
        let durationDetail = action.needsDurationSlider ? " \(durationToUse)分钟" : ""
        VehicleEventLogStore.shared.add(.action, "快捷操作执行", detail: "\(label)\(temperatureDetail)\(durationDetail)")

        let startTime = Date()
        let minimumLoadingDuration: TimeInterval = 0.35

        onConfirm(
            action,
            action.needsTemperatureSlider ? temperatureToUse : nil,
            action.needsDurationSlider ? durationToUse : nil
        ) { executionResult in
            let elapsed = Date().timeIntervalSince(startTime)
            let delay = max(0, minimumLoadingDuration - elapsed)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                isExecuting = false
                commandResult = executionResult.popupResult
                resultMessage = executionResult.popupMessage
                resultButtonTitle = executionResult.popupButtonTitle
                VehicleEventLogStore.shared.add(executionResult.logCategory, executionResult.logTitle, detail: executionResult.logDetail)
                let resultShownMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let timingDetail: String
                if let timing = executionResult.timing {
                    timingDetail = "confirm→result=\(resultShownMs)ms, \(timing.summary)"
                } else {
                    timingDetail = "confirm→result=\(resultShownMs)ms"
                }
                VehicleEventLogStore.shared.add(.action, "快捷操作耗时", detail: "\(executionResult.command.title)：\(timingDetail)")

                switch executionResult.state {
                case .feedbackOnly, .planned, .sent, .completed:
                    VibrationPattern.shortSingle.play(intensity: 0.55)
                case .failed(_), .timedOut(_):
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + executionResult.autoDismissDelay) {
                    withAnimation(PopupMotion.dismissEase) { isPresented = false }
                }
            }
        }
    }
}

private struct PopupDurationSlider: View {
    let title: String
    @Binding var durationMinutes: Double
    let range: ClosedRange<Double>
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                Spacer()
                Text("\(Int(durationMinutes)) 分钟")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
            }
            Slider(value: $durationMinutes, in: range, step: 1)
                .tint(tint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private extension VehicleCommandExecutionResult {
    var popupResult: CommandResult {
        switch state {
        case .feedbackOnly, .sent, .completed: return .success
        case .planned: return .success
        case .failed(_): return .failure
        case .timedOut(_): return .timeout
        }
    }

    var popupButtonTitle: String {
        switch state {
        case .feedbackOnly: return "已反馈 ✓"
        case .sent: return "已发送"
        case .completed: return "已完成"
        case .planned: return "已准备"
        case .failed(_): return "执行失败"
        case .timedOut(_): return "连接超时"
        }
    }

    var popupMessage: String {
        switch state {
        case .feedbackOnly:
            return userMessage.isEmpty ? "操作已完成" : userMessage
        case .sent:
            return userMessage.isEmpty ? "指令已发送，等待车辆状态更新" : userMessage
        case .completed:
            return userMessage.isEmpty ? "操作已完成" : userMessage
        case .planned:
            return userMessage.isEmpty ? "控制请求已准备就绪" : userMessage
        case .failed(_), .timedOut(_):
            return userMessage.isEmpty ? "指令未成功，请稍后重试" : userMessage
        }
    }

    var autoDismissDelay: TimeInterval {
        switch state {
        case .feedbackOnly, .planned, .sent, .completed: return 1.8
        case .failed(_), .timedOut(_): return 2.2
        }
    }

    var logCategory: VehicleEventLogCategory {
        switch state {
        case .failed(_), .timedOut(_): return .error
        default: return .action
        }
    }

    var logTitle: String {
        switch state {
        case .feedbackOnly: return "快捷操作反馈完成"
        case .planned: return "控制请求已生成"
        case .sent: return "控制请求已下发"
        case .completed: return "控制请求已回包"
        case .failed(_): return "控制请求失败"
        case .timedOut(_): return "控制请求超时"
        }
    }

    var logDetail: String {
        let message = popupMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? command.title : "\(command.title)：\(message)"
    }
}
