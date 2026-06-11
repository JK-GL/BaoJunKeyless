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
            return state.power == .unknown ? "snowflake" : (state.power == .off ? "snowflake" : "fan")
        case .windowToggle:
            return state.windowsClosed == false ? "window.horizontal.open" : "window.horizontal.closed"
        case .quickCool:     return "snowflake"
        }
    }

    /// 根据车辆状态动态返回标签
    func label(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "解锁" : "锁车"
        case .remoteStart:   return "启动"
        case .findCar:       return "寻车"
        case .acToggle:
            // TODO: 接入 MQTT 后根据 acStatus 联动
            return "空调"
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
        case .quickCool:     return Color(red: 0.3, green: 0.8, blue: 0.95)
        }
    }

    func resolvedColor(state: VehicleState) -> Color {
        switch self {
        case .lockUnlock:
            return state.locked == true ? AppTheme.green : AppTheme.red
        case .acToggle:
            return AppTheme.accent
        case .windowToggle:
            return Color(red: 0.22, green: 0.74, blue: 1.0)
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
        case .acToggle:      return "确认操作"
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
        case .acToggle:      return "将发送空调控制指令，可调节设定温度"
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
        self._temperature = State(initialValue: action == .quickCool ? 17 : 22)
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
            VStack(spacing: 0) {
                stateSummary

                if action.needsTemperatureSlider {
                    temperatureSlider
                        .padding(.top, 12)
                }

                if let result = executionResult {
                    resultBanner(result)
                        .padding(.top, 12)
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

    // MARK: - 状态摘要
    @ViewBuilder
    private var stateSummary: some View {
        let items = stateItemsForAction()
        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(item.color)
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text(item.value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    if i < items.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1, height: 36)
                    }
                }
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }

    private struct StateItem {
        let icon: String
        let label: String
        let value: String
        let color: Color
    }

    private func stateItemsForAction() -> [StateItem] {
        switch action {
        case .lockUnlock:
            return [
                StateItem(icon: vehicleState.locked == true ? "lock.fill" : "lock.open.fill",
                          label: "车锁", value: vehicleState.locked == true ? "已锁" : "未锁",
                          color: vehicleState.locked == true ? AppTheme.green : AppTheme.red),
                StateItem(icon: "gearshape.fill", label: "档位",
                          value: vehicleState.gear.title, color: AppTheme.accent),
                StateItem(icon: "car.fill", label: "车门",
                          value: vehicleState.doorsClosed == true ? "全关" : "未关",
                          color: vehicleState.doorsClosed == true ? AppTheme.green : AppTheme.orange)
            ]
        case .remoteStart:
            return [
                StateItem(icon: "key.fill", label: "电源",
                          value: vehicleState.power.title, color: AppTheme.orange),
                StateItem(icon: "gearshape.fill", label: "档位",
                          value: vehicleState.gear.title, color: AppTheme.accent)
            ]
        case .findCar:
            return []
        case .acToggle:
            return [
                StateItem(icon: "thermometer", label: "设定温度",
                          value: "\(Int(temperature))°C", color: AppTheme.accent),
                StateItem(icon: "snowflake", label: "空调",
                          value: "待控制", color: Color.white.opacity(0.6))
            ]
        case .windowToggle:
            return [
                StateItem(icon: vehicleState.windowsClosed == false ? "window.horizontal.open" : "window.horizontal.closed",
                          label: "车窗",
                          value: vehicleState.windowsClosed == true ? "已关" : "未关",
                          color: vehicleState.windowsClosed == true ? AppTheme.green : AppTheme.orange),
                StateItem(icon: "car.fill", label: "车门",
                          value: vehicleState.doorsClosed == true ? "全关" : "未关",
                          color: vehicleState.doorsClosed == true ? AppTheme.green : AppTheme.orange)
            ]
        case .quickCool:
            return [
                StateItem(icon: "thermometer", label: "设定温度",
                          value: "\(Int(temperature))°C", color: AppTheme.accent),
                StateItem(icon: "snowflake", label: "风量",
                          value: "7", color: AppTheme.accent)
            ]
        }
    }

    // MARK: - 温度滑块
    private var temperatureSlider: some View {
        VStack(spacing: 8) {
            HStack {
                Text("设定温度")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                Spacer()
                Text("\(Int(temperature))°C")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
            }
            Slider(value: $temperature, in: 16...32, step: 1)
                .tint(accentColor)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - 执行结果横幅
    @ViewBuilder
    private func resultBanner(_ result: CommandResult) -> some View {
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

    // MARK: - 执行指令
    private func executeCommand() {
        guard !isExecuting else { return }

        // 发送震动
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        isExecuting = true
        executionResult = nil

        let temp = action.needsTemperatureSlider ? temperature : nil

        // 记录日志
        vehicleLog.add(.action, "发送指令", detail: "\(action.label(state: vehicleState)) \(Int(temperature))°C")

        // TODO: 接入真正的指令发送（BLE / MQTT / 云端 API）
        // 模拟延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isExecuting = false

            // 模拟成功
            executionResult = .success
            VibrationPattern.longShortDouble.play(intensity: 0.7)

            vehicleLog.add(.action, "指令成功", detail: "\(action.label(state: vehicleState)) \(Int(temperature))°C")

            // 1.5 秒后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
            }

            onConfirm(action, temp)
        }
    }
}

// MARK: - CommandResult 辅助
private extension CommandConfirmPopup.CommandResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
