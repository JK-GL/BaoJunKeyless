import SwiftUI

// MARK: - 车控指令类型
enum CommandAction: String, Identifiable {
    case lockUnlock     // 解锁/锁车（状态联动）
    case remoteStart    // 远程启动
    case findCar        // 寻车
    case acToggle       // 空调开关（状态联动）
    case tempAdjust     // 温度调节
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
        case .tempAdjust:    return "thermometer"
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
        case .tempAdjust:    return "温度"
        case .quickCool:     return "快冷"
        }
    }

    /// 主题色
    var color: Color {
        switch self {
        case .lockUnlock:    return AppTheme.green   // 默认绿，运行时根据 locked 切换
        case .remoteStart:   return AppTheme.orange
        case .findCar:       return AppTheme.purple
        case .acToggle:      return AppTheme.accent
        case .tempAdjust:    return AppTheme.orange
        case .quickCool:     return Color(red: 0.3, green: 0.8, blue: 0.95)
        }
    }

    /// 运行时颜色（根据状态）
    func resolvedColor(state: VehicleState) -> Color {
        switch self {
        case .lockUnlock:
            return state.locked == true ? AppTheme.green : AppTheme.red
        case .acToggle:
            // TODO: 接入 MQTT 后根据 acStatus 切换
            return AppTheme.accent
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
        case .tempAdjust:    return "确认设定"
        case .quickCool:     return "确认快速降温"
        }
    }

    /// 确认弹窗说明
    func confirmMessage(state: VehicleState) -> String {
        switch self {
        case .lockUnlock:
            return state.locked == true ? "将发送解锁指令到车辆" : "将发送锁车指令到车辆"
        case .remoteStart:   return "需要 PEPS 鉴权，将通过蓝牙发送启动指令"
        case .findCar:       return "车辆将双闪鸣笛，方便定位"
        case .acToggle:      return "将发送空调开关指令"
        case .tempAdjust:    return "拖动滑块设定空调温度"
        case .quickCool:     return "17°C · 风量 7 · 10 分钟"
        }
    }

    /// 是否需要温度滑块
    var needsTemperatureSlider: Bool {
        self == .tempAdjust
    }
}

// MARK: - 车控指令确认弹窗
struct CommandConfirmSheet: View {
    @EnvironmentObject var vehicleLog: VehicleEventLogStore

    let action: CommandAction
    let vehicleState: VehicleState
    let onConfirm: (CommandAction, Double?) -> Void

    @State private var temperature: Double = 22
    @State private var isExecuting = false
    @State private var executionResult: CommandResult? = nil
    @Environment(\.dismiss) private var dismiss

    enum CommandResult {
        case success
        case failure(String)
    }

    private var accentColor: Color {
        action.resolvedColor(state: vehicleState)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部拖拽条
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.2))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // 图标
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: action.icon(state: vehicleState))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            .padding(.bottom, 12)

            // 标题
            Text(action.label(state: vehicleState))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 6)

            // 说明
            Text(action.confirmMessage(state: vehicleState))
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            // 车辆状态摘要
            stateSummary
                .padding(.bottom, 16)

            // 温度滑块（仅温度调节）
            if action.needsTemperatureSlider {
                temperatureSlider
                    .padding(.bottom, 16)
            }

            // 执行结果
            if let result = executionResult {
                resultBanner(result)
                    .padding(.bottom, 12)
            }

            // 按钮
            VStack(spacing: 10) {
                Button(action: executeCommand) {
                    HStack(spacing: 8) {
                        if isExecuting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        }
                        Text(isExecuting ? "执行中…" : action.confirmTitle(state: vehicleState))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isExecuting ? Color.white.opacity(0.5) : accentColor)
                    )
                }
                .disabled(isExecuting)

                Button(action: { dismiss() }) {
                    Text("取消")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
                StateItem(icon: "thermometer", label: "车内",
                          value: "22°C", color: AppTheme.accent),
                StateItem(icon: "snowflake", label: "空调",
                          value: "关闭", color: Color.white.opacity(0.45))
            ]
        case .tempAdjust:
            return [
                StateItem(icon: "thermometer", label: "车内",
                          value: "22°C", color: AppTheme.accent),
                StateItem(icon: "snowflake", label: "空调",
                          value: "关闭", color: Color.white.opacity(0.45))
            ]
        case .quickCool:
            return [
                StateItem(icon: "thermometer", label: "车内",
                          value: "22°C", color: AppTheme.accent),
                StateItem(icon: "snowflake", label: "空调",
                          value: "关闭", color: Color.white.opacity(0.45))
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
        vehicleLog.add(.action, "发送指令", detail: "\(action.label(state: vehicleState))")

        // TODO: 接入真正的指令发送（BLE / MQTT / 云端 API）
        // 模拟延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isExecuting = false

            // 模拟成功
            executionResult = .success
            VibrationPattern.longShortDouble.play(intensity: 0.7)

            vehicleLog.add(.action, "指令成功", detail: "\(action.label(state: vehicleState))")

            // 1.5 秒后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }

            onConfirm(action, temp)
        }
    }
}

// MARK: - CommandResult 辅助
private extension CommandConfirmSheet.CommandResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
