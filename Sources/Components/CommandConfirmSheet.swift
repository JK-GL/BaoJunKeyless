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
        case .success:  return "执行成功"
        case .failure:  return "执行失败"
        case .timeout:  return "连接超时"
        }
    }

    var message: String {
        switch self {
        case .success:  return "状态已更新"
        case .failure:  return "指令未成功，请稍后重试"
        case .timeout:  return "车辆未响应，请检查网络后重试"
        }
    }
}

// MARK: - 车控指令类型
enum CommandAction: String, Identifiable {
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

    /// 执行成功后按钮标题（官方风格）
    func successTitle(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "车辆已锁车 ✓" : "车辆已解锁 ✓"
        case .remoteStart:
            return state.power == .off ? "已远程熄火 ✓" : "车辆已启动 ✓"
        case .findCar:
            return "已触发寻车 ✓"
        case .acToggle:
            return state.acOn == true ? "空调已关闭 ✓" : "空调已开启 ✓"
        case .windowToggle:
            return state.windowsClosed == true ? "车窗已关闭 ✓" : "车窗已打开 ✓"
        case .quickCool:
            return "快速降温已开启 ✓"
        }
    }

    /// 根据车辆状态动态返回图标
    func icon(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "lock.fill" : "lock.open.fill"
        case .remoteStart:
            return state.power == .off ? "power" : "power.circle.fill"
        case .findCar:
            return "location.fill"
        case .acToggle:
            return "snowflake"
        case .windowToggle:
            return state.windowsClosed == true ? "rectangle.split.2x2.fill" : "rectangle.split.2x2"
        case .quickCool:
            return "snowflake"
        }
    }

    func label(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "锁车" : "已开锁"
        case .remoteStart:
            return state.power == .off ? "熄火" : "已启动"
        case .findCar:
            return "寻车"
        case .acToggle:
            return state.acOn == true ? "已开空调" : "关闭"
        case .windowToggle:
            return state.windowsClosed == false ? "已开窗" : "关窗"
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
            return state.locked == true ? AppTheme.green : AppTheme.red
        case .remoteStart:
            return state.power == .off ? Color(red: 0.55, green: 0.58, blue: 0.62) : AppTheme.green
        case .acToggle:
            return state.acOn == true ? AppTheme.accent : Color(red: 0.55, green: 0.58, blue: 0.62)
        case .windowToggle:
            return state.windowsClosed == true ? AppTheme.green : Color(red: 0.22, green: 0.74, blue: 1.0)
        default:
            return color
        }
    }

    /// 确认弹窗标题（官方风格）
    func confirmTitle(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "解锁车辆" : "锁车"
        case .remoteStart:   return state.power == .off ? "远程启动" : "远程熄火"
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
            return state.locked == true ? "车辆将远程解锁，车门锁会解除" : "车辆将远程上锁，确保车门已关闭"
        case .remoteStart:   return state.power == .off ? "通过蓝牙鉴权，远程启动发动机" : "车辆将远程熄火，发动机停止运转"
        case .findCar:       return "车辆将双闪鸣笛，方便您定位"
        case .acToggle:
            return state.acOn == true ? "关闭空调压缩机，停止送风" : "开启空调，可调节设定温度"
        case .windowToggle:
            return state.windowsClosed == false ? "关闭全部车窗，确保安全" : "打开全部车窗，便于通风"
        case .quickCool:     return "一键降温至 17°C · 风量 7 · 持续 10 分钟"
        }
    }

    /// 是否需要温度滑块
    var needsTemperatureSlider: Bool {
        self == .acToggle || self == .quickCool
    }
}

// MARK: - 车控指令确认弹窗（居中卡片）
struct CommandConfirmPopup: View {
    @EnvironmentObject var vehicleLog: VehicleEventLogStore

    let action: CommandAction
    let vehicleState: VehicleState
    @Binding var isPresented: Bool
    let onConfirm: (CommandAction, Double?) -> Void

    @State private var temperature: Double
    @State private var isExecuting = false
    @State private var executedState: VehicleState? = nil
    @State private var commandResult: CommandResult? = nil

    init(action: CommandAction, vehicleState: VehicleState, isPresented: Binding<Bool>, onConfirm: @escaping (CommandAction, Double?) -> Void) {
        self.action = action
        self.vehicleState = vehicleState
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        self._temperature = State(initialValue: vehicleState.acTemperature ?? (action == .quickCool ? 17 : 22))
    }

    /// 执行后显示新状态，否则显示原始状态
    private var displayState: VehicleState {
        executedState ?? vehicleState
    }

    private var accentColor: Color {
        action.resolvedColor(state: displayState)
    }

    private var resultSubtitle: String {
        if let result = commandResult {
            return result.message
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

    var body: some View {
        FloatingPopupCard(
            icon: resultIcon,
            iconColor: resultColor,
            title: action.label(state: displayState),
            subtitle: resultSubtitle,
            onClose: { withAnimation(.easeOut(duration: 0.2)) { isPresented = false } }
        ) {
            VStack(spacing: 12) {
                PopupStatusSummaryView(items: statusItemsForCurrentAction)

                if action.needsTemperatureSlider && commandResult == nil {
                    PopupTemperatureSlider(
                        title: "设定温度",
                        temperature: $temperature,
                        range: 16...32,
                        tint: accentColor
                    )
                }
            }
        } actions: {
            if let result = commandResult {
                // 执行后：结果按钮（disabled，用对应颜色背景）
                FloatingPopupPrimaryButton(
                    title: result == .success ? action.successTitle(state: executedState ?? vehicleState) : action.failureTitle(result: result),
                    color: result.color,
                    isLoading: false,
                    isDisabled: true,
                    disabledBackgroundColor: result.color,
                    action: {}
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if isExecuting {
                // 执行中：仅显示执行按钮，隐藏取消
                FloatingPopupPrimaryButton(
                    title: "执行中…",
                    color: accentColor,
                    isLoading: true,
                    isDisabled: true,
                    action: {}
                )
                .transition(.opacity)
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
                        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExecuting)
        .animation(.easeInOut(duration: 0.25), value: commandResult != nil)
    }

    private var statusItemsForCurrentAction: [PopupStatusItem] {
        let state = displayState
        switch action {
        case .lockUnlock:
            return [
                PopupStatusItem(icon: state.locked == true ? "lock.fill" : "lock.open.fill",
                                label: "车锁", value: state.locked == true ? "已锁" : "未锁",
                                color: state.locked == true ? AppTheme.green : AppTheme.red),
                PopupStatusItem(icon: "gearshape.fill", label: "档位",
                                value: state.gear.title, color: AppTheme.accent),
                PopupStatusItem(icon: "car.fill", label: "车门",
                                value: state.doorsClosed == true ? "全关" : "未关",
                                color: state.doorsClosed == true ? AppTheme.green : AppTheme.orange)
            ]
        case .remoteStart:
            let startStatusText: String
            let startStatusColor: Color
            switch state.power {
            case .off, .acc:
                startStatusText = "待启动"
                startStatusColor = AppTheme.orange
            case .on, .ready:
                startStatusText = "已启动"
                startStatusColor = AppTheme.green
            case .unknown:
                startStatusText = "未知"
                startStatusColor = Color.white.opacity(0.45)
            }
            return [
                PopupStatusItem(icon: "key.fill", label: "电源",
                                value: state.power.title, color: AppTheme.orange),
                PopupStatusItem(icon: "dot.radiowaves.left.and.right", label: "启动",
                                value: startStatusText, color: startStatusColor),
                PopupStatusItem(icon: "gearshape.fill", label: "档位",
                                value: state.gear.title, color: AppTheme.accent)
            ]
        case .findCar:
            return []
        case .acToggle:
            return [
                PopupStatusItem(icon: state.acOn == true ? "thermometer.medium" : "snowflake",
                                label: "空调",
                                value: state.acOn == true ? "已开" : "已关",
                                color: state.acOn == true ? AppTheme.green : AppTheme.accent),
                PopupStatusItem(icon: "thermometer", label: "设定温度",
                                value: "\(Int(temperature))°C", color: AppTheme.accent)
            ]
        case .windowToggle:
            return [
                PopupStatusItem(icon: state.windowsClosed == false ? "rectangle.split.2x2" : "rectangle.split.2x2.fill",
                                label: "车窗",
                                value: state.windowsClosed == true ? "已关" : "未关",
                                color: state.windowsClosed == true ? AppTheme.green : AppTheme.orange),
                PopupStatusItem(icon: "car.fill", label: "车门",
                                value: state.doorsClosed == true ? "全关" : "未关",
                                color: state.doorsClosed == true ? AppTheme.green : AppTheme.orange)
            ]
        case .quickCool:
            return [
                PopupStatusItem(icon: "thermometer", label: "设定温度",
                                value: "\(Int(temperature))°C", color: AppTheme.accent),
                PopupStatusItem(icon: "snowflake", label: "风量",
                                value: "7", color: AppTheme.accent)
            ]
        }
    }

    /// 根据动作类型，模拟执行后的车辆状态
    private func vehicleStateAfterAction(_ action: CommandAction, temperature: Double?) -> VehicleState {
        var newState = vehicleState
        switch action {
        case .lockUnlock:
            newState.locked = !(vehicleState.locked ?? true)
        case .remoteStart:
            newState.power = vehicleState.power == .off ? .ready : .off
        case .acToggle:
            newState.acOn = !(vehicleState.acOn ?? false)
            if let t = temperature { newState.acTemperature = t }
        case .windowToggle:
            newState.windowsClosed = !(vehicleState.windowsClosed ?? true)
        case .quickCool:
            newState.acOn = true
            newState.acTemperature = temperature ?? 17
        case .findCar:
            break
        }
        return newState
    }

    private func executeCommand() {
        guard !isExecuting else { return }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        isExecuting = true
        let temperatureToUse = temperature
        let label = action.label(state: vehicleState)

        vehicleLog.add(.action, "发送指令", detail: "\(label) \(action.needsTemperatureSlider ? "\(Int(temperatureToUse))°C" : "")")

        // Mock: 模拟执行延迟 + 随机成功/失败/超时
        let delay: Double = Double.random(in: 0.8...1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isExecuting = false

            // Mock 结果：90% 成功，10% 失败
            let mockResult: CommandResult = Bool.random() && Int.random(in: 0...9) == 0 ? .failure : .success
            commandResult = mockResult

            if mockResult == .success {
                executedState = vehicleStateAfterAction(action, temperature: temperatureToUse)
                VibrationPattern.longShortDouble.play(intensity: 0.7)
                vehicleLog.add(.action, "指令成功", detail: "\(action.label(state: vehicleStateAfterAction(action, temperature: temperatureToUse)))")
                onConfirm(action, action.needsTemperatureSlider ? temperatureToUse : nil)
            } else {
                VibrationPattern.shortSingle.play(intensity: 0.5)
                vehicleLog.add(.error, "指令失败", detail: "\(label) \(mockResult == .timeout ? "连接超时" : "执行失败")")
            }

            // 2 秒后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
            }
        }
    }
}


