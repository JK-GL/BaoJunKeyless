import Foundation

// MARK: - 无感动作
enum KeylessAction: String, Codable {
    case unlock
    case lock
    case powerStart

    var title: String {
        switch self {
        case .unlock:     return "解锁"
        case .lock:       return "上锁"
        case .powerStart: return "启动电源"
        }
    }
}

// MARK: - 决策结果
enum KeylessDecision: Equatable {
    case allow(action: KeylessAction, reason: String)
    case deny(action: KeylessAction, reason: String)
    case wait(action: KeylessAction, reason: String)

    var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }

    var actionTitle: String {
        switch self {
        case .allow(let a, _), .deny(let a, _), .wait(let a, _):
            return a.title
        }
    }

    var reason: String {
        switch self {
        case .allow(_, let r), .deny(_, let r), .wait(_, let r):
            return r
        }
    }

    var logLevel: String {
        switch self {
        case .allow: return "允许"
        case .deny:  return "拒绝"
        case .wait:  return "等待"
        }
    }

    // Equatable（基于 action + logLevel + reason）
    static func == (lhs: KeylessDecision, rhs: KeylessDecision) -> Bool {
        lhs.actionTitle == rhs.actionTitle && lhs.logLevel == rhs.logLevel && lhs.reason == rhs.reason
    }
}

// MARK: - 无感决策引擎
struct KeylessDecisionEngine {

    /// 无感评估上下文：用于放行 BLE 离线会话、统一新鲜度策略
    struct Context: Equatable {
        /// 本次 BLE 会话是否已鉴权成功
        var bleAuthenticated: Bool = false
        /// 车况新鲜度窗口（秒）；HTTP 60s 轮询默认 90s
        var freshnessMaxAge: TimeInterval = 90

        static let `default` = Context()
    }

    // MARK: - 解锁评估
    static func evaluateUnlock(
        state: VehicleState,
        settings: KeylessSettings,
        context: Context = .default
    ) -> KeylessDecision {
        // 1. 无感总开关
        guard settings.keylessEnabled else {
            return .deny(action: .unlock, reason: "无感开关关闭")
        }
        // 2. 解锁开关
        guard settings.unlockEnabled else {
            return .deny(action: .unlock, reason: "解锁开关关闭")
        }
        // 3. 状态可用性：
        //    - 在线：要求车况新鲜
        //    - 离线：仅 BLE 已鉴权且有 live RSSI 时允许使用最后已知车况
        if let availabilityDeny = denyIfStateUnavailable(action: .unlock, state: state, context: context) {
            return availabilityDeny
        }
        // 4. 手机靠近（只信 BLE RSSI 判定结果）
        guard state.phoneNearby else {
            return .deny(action: .unlock, reason: "手机未进入解锁范围")
        }
        // 5. 车辆已锁
        //    - locked=false：无论在线离线都拒绝（已开锁再解会循环）
        //    - locked=nil：仅 BLE 已鉴权时允许尝试
        //    - locked=true：正常放行到后续条件
        if state.locked == false {
            return .deny(action: .unlock, reason: "车辆未上锁，无需重复解锁")
        }
        if state.locked == nil && !context.bleAuthenticated {
            return .deny(action: .unlock, reason: "车锁状态未知且 BLE 未鉴权")
        }
        // 6. 车速 = 0
        if let speed = state.speed, speed > 0 {
            return .deny(action: .unlock, reason: "车辆行驶中 (\(Int(speed))km/h)")
        }
        // 7. 档位：已知非 P 才拒绝；离线 gear=unknown 不卡死无感
        if state.gear != .p && state.gear != .unknown {
            return .deny(action: .unlock, reason: "档位 \(state.gear.title)，不允许无感解锁")
        }
        if state.gear == .unknown && !context.bleAuthenticated {
            return .deny(action: .unlock, reason: "档位未知且 BLE 未鉴权")
        }
        // 8. 电源：仅明确通电/就绪时拒绝。
        //    现场车况常缺 engineStatus → power=unknown(--)，不能因此卡死无感。
        if isPowerClearlyOn(state.power) {
            return .deny(action: .unlock, reason: "车辆未熄火 (\(state.power.title))")
        }
        // 9. 物理钥匙：解锁不再因 inside 拒绝。
        //    手机数字钥匙靠近时云端 keyStatus 常误报 inside，会把无感解锁彻底卡死。

        var reason: String
        if !state.online && context.bleAuthenticated {
            reason = "满足无感解锁条件（BLE 离线会话）"
        } else {
            reason = "满足无感解锁条件"
        }
        if state.power == .unknown {
            reason += " · 电源未知按熄火评估"
        }
        if state.gear == .unknown {
            reason += " · 档位未知"
        }
        if state.locked == nil {
            reason += " · 车锁未知按可解锁评估"
        }
        return .allow(action: .unlock, reason: reason)
    }


    // MARK: - 启动电源评估（BLE powerOnReady，替代无感解锁）
    static func evaluatePowerStart(
        state: VehicleState,
        settings: KeylessSettings,
        context: Context = .default
    ) -> KeylessDecision {
        guard settings.keylessEnabled else {
            return .deny(action: .powerStart, reason: "无感开关关闭")
        }
        guard settings.powerStartEnabled else {
            return .deny(action: .powerStart, reason: "启动电源开关关闭")
        }
        // 必须 BLE 已鉴权，才能发 powerOnReady
        guard context.bleAuthenticated else {
            return .deny(action: .powerStart, reason: "蓝牙未连接，无法启动电源")
        }
        if let availabilityDeny = denyIfStateUnavailable(action: .powerStart, state: state, context: context) {
            return availabilityDeny
        }
        guard state.phoneNearby else {
            return .deny(action: .powerStart, reason: "尚未靠近车辆")
        }
        // 已明确上电则不再重复发
        if state.power == .on || state.power == .ready {
            return .deny(action: .powerStart, reason: "车辆已上电 (\(state.power.title))")
        }
        if let speed = state.speed, speed > 0 {
            return .deny(action: .powerStart, reason: "车辆行驶中 (\(Int(speed))km/h)")
        }
        if state.gear != .p && state.gear != .unknown {
            return .deny(action: .powerStart, reason: "档位 \(state.gear.title)，不允许无感启动电源")
        }
        if state.gear == .unknown && !context.bleAuthenticated {
            return .deny(action: .powerStart, reason: "档位未知且 BLE 未鉴权")
        }

        var reason = "满足启动电源条件"
        if state.power == .unknown || state.power == .off {
            reason += " · 电源按待上电评估"
        }
        if state.gear == .unknown {
            reason += " · 档位未知"
        }
        return .allow(action: .powerStart, reason: reason)
    }

    static func evaluatePowerStartWithDelay(
        state: VehicleState,
        settings: KeylessSettings,
        phoneNearbySince: Date?,
        context: Context = .default
    ) -> KeylessDecision {
        let decision = evaluatePowerStart(state: state, settings: settings, context: context)
        guard case .allow = decision else { return decision }
        // 复用解锁靠近确认时长
        let delay = max(settings.unlockApproachDuration, 0)
        guard delay > 0 else { return decision }
        guard let phoneNearbySince else {
            return .wait(action: .powerStart, reason: "手机靠近，等待启动确认")
        }
        let elapsed = Date().timeIntervalSince(phoneNearbySince)
        guard elapsed >= delay else {
            return .wait(action: .powerStart, reason: "手机靠近，等待启动确认")
        }
        return decision
    }

    // MARK: - 上锁评估
    static func evaluateLock(
        state: VehicleState,
        settings: KeylessSettings,
        context: Context = .default
    ) -> KeylessDecision {
        // 1. 无感总开关
        guard settings.keylessEnabled else {
            return .deny(action: .lock, reason: "无感开关关闭")
        }
        // 2. 上锁开关
        guard settings.lockEnabled else {
            return .deny(action: .lock, reason: "上锁开关关闭")
        }
        // 3. 状态可用性（同解锁）
        if let availabilityDeny = denyIfStateUnavailable(action: .lock, state: state, context: context) {
            return availabilityDeny
        }
        // 4. 手机远离
        guard state.phoneFarAway else {
            return .deny(action: .lock, reason: "手机未离开上锁范围")
        }
        // 5. 车辆未锁
        //    - locked=true：拒绝重复上锁（含离线本地回写后的已锁）
        //    - locked=nil：仅 BLE 已鉴权时允许尝试
        if state.locked == true {
            return .deny(action: .lock, reason: "车辆已上锁，无需重复上锁")
        }
        if state.locked == nil && !context.bleAuthenticated {
            return .deny(action: .lock, reason: "车锁状态未知且 BLE 未鉴权")
        }

        // 6/7. 未关不自动上锁（依赖上锁弹窗）：
        //    - 仅在 lockPopup + lockRequireClosedBody 同时开启时生效。
        //    - 仅明确“门/尾门未关”才拒绝；状态未知不卡死 BLE 无感上锁。
        //    - 车窗不参与预检：只提醒不拦锁；点名推送在拒绝后走 HTTP。
        if settings.lockPopup && settings.lockRequireClosedBody {
            if state.doorsClosed == false {
                return .deny(action: .lock, reason: "车门未关闭")
            }
            if state.driverDoorOpen == true {
                return .deny(action: .lock, reason: "主驾门未关闭")
            }
            if state.trunkOpen == true {
                return .deny(action: .lock, reason: "尾门未关闭")
            }
        }
        // 8. 车速 = 0
        if let speed = state.speed, speed > 0 {
            return .deny(action: .lock, reason: "车辆行驶中 (\(Int(speed))km/h)")
        }
        // 9. 档位：已知非 P 才拒绝；unknown + BLE 鉴权放行
        if state.gear != .p && state.gear != .unknown {
            return .deny(action: .lock, reason: "档位 \(state.gear.title)，不允许无感上锁")
        }
        if state.gear == .unknown && !context.bleAuthenticated {
            return .deny(action: .lock, reason: "档位未知且 BLE 未鉴权")
        }
        // 10. 电源：仅明确通电/就绪时拒绝；unknown 不拦
        if isPowerClearlyOn(state.power) {
            return .deny(action: .lock, reason: "车辆未熄火 (\(state.power.title))")
        }
        // 11. 物理钥匙在车内：
        //    - 无手机 BLE 鉴权：按实体钥匙风险拒绝
        //    - 已 BLE 鉴权：云端 inside 常为数字钥匙误报，不拦截远离上锁
        // 离线/陈旧的 keyStatus=2 不能当实体钥匙；仅在线新鲜且无 BLE 会话时才提示
        if state.physicalKeyPosition == .inside && !context.bleAuthenticated {
            if state.online && state.isFresh(maxAge: context.freshnessMaxAge) {
                return .deny(action: .lock, reason: "云端钥匙感应在车内")
            }
            // 离线或过期：忽略，避免误拦无感/误显示物理钥匙
        }

        var reason: String
        if !state.online && context.bleAuthenticated {
            reason = "满足无感上锁条件（BLE 离线会话）"
        } else {
            reason = "满足无感上锁条件"
        }
        if state.power == .unknown {
            reason += " · 电源未知按熄火评估"
        }
        if state.gear == .unknown {
            reason += " · 档位未知"
        }
        if state.locked == nil {
            reason += " · 车锁未知按可上锁评估"
        }
        if state.physicalKeyPosition == .inside && context.bleAuthenticated {
            reason += " · 云端钥匙车内按数字钥匙忽略"
        }
        return .allow(action: .lock, reason: reason)
    }

    /// 仅当电源明确处于通电链路时才视为“未熄火”
    private static func isPowerClearlyOn(_ power: VehiclePowerState) -> Bool {
        switch power {
        case .on, .ready, .acc:
            return true
        case .off, .unknown:
            return false
        }
    }

    /// 在线要求新鲜车况；过期时若 BLE 已鉴权可用最后车况。
    /// 离线仅允许 BLE 已鉴权会话做无感。
    private static func denyIfStateUnavailable(
        action: KeylessAction,
        state: VehicleState,
        context: Context
    ) -> KeylessDecision? {
        if state.online {
            if state.isFresh(maxAge: context.freshnessMaxAge) {
                return nil
            }
            // 在线但车况过期：BLE 已鉴权 + (有 live RSSI 或上锁远离) 时放行
            if context.bleAuthenticated && (state.hasLiveBLEProximity || action == .lock) {
                return nil
            }
            let age = Int(Date().timeIntervalSince(state.timestamp))
            return .deny(action: action, reason: "车辆状态 \(age)s 未更新")
        }

        // 离线：必须 BLE 已鉴权
        guard context.bleAuthenticated else {
            return .deny(action: action, reason: "车辆离线且 BLE 未鉴权")
        }
        // 解锁要求 live RSSI；上锁允许信号丢失后的远离评估
        if action == .unlock && !state.hasLiveBLEProximity {
            return .deny(action: action, reason: "车辆离线且无 BLE 靠近信号")
        }
        return nil
    }

    static func evaluateUnlockWithDelay(
        state: VehicleState,
        settings: KeylessSettings,
        phoneNearbySince: Date?,
        context: Context = .default
    ) -> KeylessDecision {
        let decision = evaluateUnlock(state: state, settings: settings, context: context)
        guard case .allow = decision else { return decision }
        let delay = max(settings.unlockApproachDuration, 0)
        guard delay > 0 else { return decision }
        guard let phoneNearbySince else {
            return .wait(action: .unlock, reason: "手机靠近，等待解锁确认")
        }
        let elapsed = Date().timeIntervalSince(phoneNearbySince)
        guard elapsed >= delay else {
            return .wait(action: .unlock, reason: "手机靠近，等待解锁确认")
        }
        return decision
    }

    static func evaluateLockWithDelay(
        state: VehicleState,
        settings: KeylessSettings,
        phoneFarAwaySince: Date?,
        context: Context = .default
    ) -> KeylessDecision {
        let decision = evaluateLock(state: state, settings: settings, context: context)
        guard case .allow = decision else { return decision }
        let delay = max(settings.lockDelay, 0)
        guard delay > 0 else { return decision }
        guard let phoneFarAwaySince else {
            return .wait(action: .lock, reason: "手机远离，等待上锁延迟")
        }
        let elapsed = Date().timeIntervalSince(phoneFarAwaySince)
        guard elapsed >= delay else {
            return .wait(action: .lock, reason: "手机远离，等待上锁延迟")
        }
        return decision
    }

    // MARK: - 日志输出
    /// 将决策结果格式化为日志详情字符串
    static func logDetail(
        decision: KeylessDecision,
        state: VehicleState,
        settings: KeylessSettings
    ) -> String {
        var parts: [String] = []

        parts.append(decision.reason)

        if let rssi = state.bleRssi {
            parts.append("rssi=\(rssi)")
        }
        if let locked = state.locked {
            parts.append("locked=\(locked)")
        }
        parts.append("gear=\(state.gear.title)")
        parts.append("power=\(state.power.title)")
        if let doors = state.doorsClosed {
            parts.append("doors=\(doors ? "closed" : "open")")
        }
        if let trunk = state.trunkOpen, trunk {
            parts.append("trunk=open")
        }
        switch state.physicalKeyPosition {
        case .inside:
            // 云端 keyStatus=2；手机 BLE 靠近时常见数字钥匙误报，不等于确认实体钥匙在车内
            parts.append("key=inside(cloud)")
        case .outside:
            parts.append("key=outside")
        case .farAway:
            parts.append("key=far")
        case .unknown:
            parts.append("key=unknown")
        }
        if !state.online {
            parts.append("offline")
        }
        if state.hasLiveBLEProximity {
            parts.append("bleLive")
        }

        return parts.joined(separator: " | ")
    }

    // MARK: - 评估 + 日志（一步到位）
    /// 评估解锁并写入日志
    @discardableResult
    static func evaluateAndLog(
        unlock state: VehicleState,
        settings: KeylessSettings,
        log: VehicleEventLogStore,
        context: Context = .default
    ) -> KeylessDecision {
        let decision = evaluateUnlock(state: state, settings: settings, context: context)
        let detail = logDetail(decision: decision, state: state, settings: settings)
        switch decision {
        case .allow:
            log.add(.keyless, "解锁允许", detail: detail)
        case .deny:
            log.add(.keyless, "解锁拒绝", detail: detail)
        case .wait:
            log.add(.keyless, "解锁等待", detail: detail)
        }
        return decision
    }

    /// 评估上锁并写入日志
    @discardableResult
    static func evaluateAndLog(
        lock state: VehicleState,
        settings: KeylessSettings,
        log: VehicleEventLogStore,
        context: Context = .default
    ) -> KeylessDecision {
        let decision = evaluateLock(state: state, settings: settings, context: context)
        let detail = logDetail(decision: decision, state: state, settings: settings)
        switch decision {
        case .allow:
            log.add(.keyless, "上锁允许", detail: detail)
        case .deny:
            log.add(.keyless, "上锁拒绝", detail: detail)
        case .wait:
            log.add(.keyless, "上锁等待", detail: detail)
        }
        return decision
    }
}
