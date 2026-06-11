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

    /// 根据车辆状态动态返回图标
    func icon(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "lock.open.fill" : "lock.fill"
        case .remoteStart:   return "dot.radiowaves.left.and.right"
        case .findCar:       return "location.fill"
        case .acToggle:
            return state.acOn == true ? "fan" : "snowflake"
        case .windowToggle:
            return state.windowsClosed == false ? "window.horizontal.open" : "window.horizontal.closed"
        case .quickCool:     return "snowflake"
        }
    }

    func label(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "解锁" : "锁车"
        case .remoteStart:   return "启动"
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
        case .remoteStart:   return "确认启动"
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
        case .remoteStart:   return "需要 PEPS 鉴权，将通过蓝牙发送启动指令"
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
    @State private var executionResult: CommandResult? = nil

    enum CommandResult {
        case success
        case failure(String)
    }

    init(action: CommandAction, vehicleState: VehicleState, isPresented: Binding<Bool>, onConfirm: @escaping (CommandAction, Double?) -> Void) {
        self.action = action
        self.vehicleState = vehicleState
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        self._temperature = State(initialValue: vehicleState.acTemperature ?? (action == .quickCool ? 17 : 22))
    }

    private var accentColor: Color {
        action.resolvedColor(state: vehicleState)
    }

    var body: some View {
        FloatingPopupCard(
            icon: action.icon(state: vehicleState),
            iconColor: accentColor,
            title: action.label(state: vehicleState),
            subtitle: action.confirmMessage(state: vehicleState),
            onClose: { withAnimation(.easeOut(duration: 0.2)) { isPresented = false } }
        ) {
            VStack(spacing: 12) {
                PopupStatusSummaryView(items: statusItemsForCurrentAction)

                if action.needsTemperatureSlider {
                    PopupTemperatureSlider(
                        title: "设定温度",
                        temperature: $temperature,
                        range: 16...32,
                        tint: accentColor
                    )
                }

                if let result = executionResult {
                    PopupCommandResultBanner(result: result)
                }
            }
        } actions: {
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

    private var statusItemsForCurrentAction: [PopupStatusItem] {
        switch action {
        case .lockUnlock:
            return [
                PopupStatusItem(icon: vehicleState.locked == true ? "lock.fill" : "lock.open.fill",
                                label: "车锁", value: vehicleState.locked == true ? "已锁" : "未锁",
                                color: vehicleState.locked == true ? AppTheme.green : AppTheme.red),
                PopupStatusItem(icon: "gearshape.fill", label: "档位",
                                value: vehicleState.gear.title, color: AppTheme.accent),
                PopupStatusItem(icon: "car.fill", label: "车门",
                                value: vehicleState.doorsClosed == true ? "全关" : "未关",
                                color: vehicleState.doorsClosed == true ? AppTheme.green : AppTheme.orange)
            ]
        case .remoteStart:
            return [
                PopupStatusItem(icon: "key.fill", label: "电源",
                                value: vehicleState.power.title, color: AppTheme.orange),
                PopupStatusItem(icon: "gearshape.fill", label: "档位",
                                value: vehicleState.gear.title, color: AppTheme.accent)
            ]
        case .findCar:
            return []
        case .acToggle:
            return [
                PopupStatusItem(icon: vehicleState.acOn == true ? "fan" : "snowflake",
                                label: "空调",
                                value: vehicleState.acOn == true ? "已开" : "已关",
                                color: vehicleState.acOn == true ? AppTheme.green : AppTheme.accent),
                PopupStatusItem(icon: "thermometer", label: "设定温度",
                                value: "\(Int(temperature))°C", color: AppTheme.accent)
            ]
        case .windowToggle:
            return [
                PopupStatusItem(icon: vehicleState.windowsClosed == false ? "window.horizontal.open" : "window.horizontal.closed",
                                label: "车窗",
                                value: vehicleState.windowsClosed == true ? "已关" : "未关",
                                color: vehicleState.windowsClosed == true ? AppTheme.green : AppTheme.orange),
                PopupStatusItem(icon: "car.fill", label: "车门",
                                value: vehicleState.doorsClosed == true ? "全关" : "未关",
                                color: vehicleState.doorsClosed == true ? AppTheme.green : AppTheme.orange)
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

    private func executeCommand() {
        guard !isExecuting else { return }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        isExecuting = true
        executionResult = nil

        let temperatureToUse = temperature
        let label = action.label(state: vehicleState)

        vehicleLog.add(.action, "发送指令", detail: "\(label) \(action.needsTemperatureSlider ? "\(Int(temperatureToUse))°C" : "")")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isExecuting = false
            executionResult = .success
            VibrationPattern.longShortDouble.play(intensity: 0.7)
            vehicleLog.add(.action, "指令成功", detail: "\(label) \(action.needsTemperatureSlider ? "\(Int(temperatureToUse))°C" : "")")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
            }

            onConfirm(action, action.needsTemperatureSlider ? temperatureToUse : nil)
        }
    }
}

// MARK: - 指令结果横幅组件
private struct PopupCommandResultBanner: View {
    let result: CommandConfirmPopup.CommandResult

    var body: some View {
        HStack(spacing: 8) {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.green)
                Text("指令已发送")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.green)
            case .failure(let reason):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppTheme.red)
                Text(reason)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.red)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((result.isSuccess ? AppTheme.green : AppTheme.red).opacity(0.1))
        )
    }
}

private extension CommandConfirmPopup.CommandResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
