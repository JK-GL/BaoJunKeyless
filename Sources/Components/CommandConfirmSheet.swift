import SwiftUI

// MARK: - 车控指令类型
enum CommandAction: String, Identifiable {
    case lockUnlock     // 解锁/锁车（状态联动）
    case remoteStart    // 远程启动
    case findCar        // 寻车
    case acToggle       // 空调开关（状态联动）
    case windowToggle   // 车窗开关（状态联动）
    case quickCool      // 快速降温

    var id: String { rawValue }

    /// 执行成功后按钮标题（绿色 ✓）
    func successTitle(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "已锁车 ✓" : "已解锁 ✓"
        case .remoteStart:
            return state.power == .off ? "已熄火 ✓" : "已启动 ✓"
        case .findCar:
            return "已寻车 ✓"
        case .acToggle:
            return state.acOn == true ? "空调已开 ✓" : "空调已关 ✓"
        case .windowToggle:
            return state.windowsClosed == true ? "车窗已关 ✓" : "车窗已开 ✓"
        case .quickCool:
            return "快速降温已开 ✓"
        }
    }

    /// 根据车辆状态动态返回图标
    func icon(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "lock.open.fill" : "lock.fill"
        case .remoteStart:   return state.power == .off ? "dot.radiowaves.left.and.right" : "power"
        case .findCar:       return "location.fill"
        case .acToggle:
            return state.acOn == true ? "thermometer.medium" : "snowflake"
        case .windowToggle:
            return state.windowsClosed == false ? "rectangle.split.2x2" : "rectangle.split.2x2.fill"
        case .quickCool:     return "snowflake"
        }
    }

    func label(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "解锁" : "锁车"
        case .remoteStart:   return state.power == .off ? "启动" : "已启动"
        case .findCar:       return "寻车"
        case .acToggle:
            return state.acOn == true ? "关闭空调" : "打开空调"
        case .windowToggle:
            return state.windowsClosed == false ? "关窗" : "开窗"
        case .quickCool:     return "快冷"
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
            return state.power == .off ? AppTheme.orange : AppTheme.green
        case .acToggle:
            return state.acOn == true ? AppTheme.accent : Color(red: 0.55, green: 0.58, blue: 0.62)
        case .windowToggle:
            return state.windowsClosed == true ? AppTheme.green : Color(red: 0.22, green: 0.74, blue: 1.0)
        default:
            return color
        }
    }

    /// 确认弹窗标题
    func confirmTitle(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "确认解锁" : "确认锁车"
        case .remoteStart:   return state.power == .off ? "确认启动" : "确认熄火"
        case .findCar:       return "确认寻车"
        case .acToggle:
            return state.acOn == true ? "确认关闭空调" : "确认打开空调"
        case .windowToggle:
            return state.windowsClosed == false ? "确认关窗" : "确认开窗"
        case .quickCool:     return "确认快速降温"
        }
    }

    func confirmMessage(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "将发送解锁指令到车辆" : "将发送锁车指令到车辆"
        case .remoteStart:   return state.power == .off ? "需要 PEPS 鉴权，将通过蓝牙发送启动指令" : "将发送远程熄火指令"
        case .findCar:       return "车辆将双闪鸣笛，方便定位"
        case .acToggle:
            return state.acOn == true ? "将发送关闭空调指令" : "将发送打开空调指令，可调节设定温度"
        case .windowToggle:
            return state.windowsClosed == false ? "将发送关闭车窗指令" : "将发送打开车窗指令"
        case .quickCool:     return "17°C · 风量 7 · 10 分钟"
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

    var body: some View {
        FloatingPopupCard(
            icon: action.icon(state: displayState),
            iconColor: accentColor,
            title: action.label(state: displayState),
            subtitle: executedState != nil ? "状态已更新" : action.confirmMessage(state: vehicleState),
            onClose: { withAnimation(.easeOut(duration: 0.2)) { isPresented = false } }
        ) {
            VStack(spacing: 12) {
                PopupStatusSummaryView(items: statusItemsForCurrentAction)

                if action.needsTemperatureSlider && executedState == nil {
                    PopupTemperatureSlider(
                        title: "设定温度",
                        temperature: $temperature,
                        range: 16...32,
                        tint: accentColor
                    )
                }
            }
        } actions: {
            if let result = executedState {
                // 执行后：绿色成功按钮（disabled，不可再点）
                FloatingPopupPrimaryButton(
                    title: action.successTitle(state: result),
                    color: AppTheme.green,
                    isLoading: false,
                    isDisabled: true,
                    action: {}
                )
                .transition(.opacity)
            } else {
                // 执行前：确认 + 取消
                VStack(spacing: 8) {
                    FloatingPopupPrimaryButton(
                        title: isExecuting ? "执行中…" : action.confirmTitle(state: vehicleState),
                        color: accentColor,
                        isLoading: isExecuting,
                        isDisabled: isExecuting,
                        action: executeCommand
                    )

                    FloatingPopupSecondaryButton(
                        title: "取消",
                        textColor: Color.white.opacity(0.6)
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                    }
                }
            }
        }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isExecuting = false
            // 执行完成，切换到新状态
            executedState = vehicleStateAfterAction(action, temperature: temperatureToUse)
            VibrationPattern.longShortDouble.play(intensity: 0.7)
            vehicleLog.add(.action, "指令成功", detail: "\(action.label(state: vehicleStateAfterAction(action, temperature: temperatureToUse)))")

            onConfirm(action, action.needsTemperatureSlider ? temperatureToUse : nil)

            // 2.5 秒后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
            }
        }
    }
}


