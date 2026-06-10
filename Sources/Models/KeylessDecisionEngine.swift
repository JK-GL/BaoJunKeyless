import Foundation

// MARK: - 无感动作
enum KeylessAction: String, Codable {
    case unlock
    case lock

    var title: String {
        switch self {
        case .unlock: return "解锁"
        case .lock:   return "上锁"
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

    // MARK: - 解锁评估
    static func evaluateUnlock(
        state: VehicleState,
        settings: KeylessSettings
    ) -> KeylessDecision {
        // 1. 无感总开关
        guard settings.keylessEnabled else {
            return .deny(action: .unlock, reason: "无感开关关闭")
        }
        // 2. 解锁开关
        guard settings.unlockEnabled else {
            return .deny(action: .unlock, reason: "解锁开关关闭")
        }
        // 3. 状态新鲜度（在线时才检查；离线直接拒绝）
        guard state.online else {
            return .deny(action: .unlock, reason: "车辆离线")
        }
        guard state.isFresh() else {
            let age = Int(Date().timeIntervalSince(state.timestamp))
            return .deny(action: .unlock, reason: "车辆状态 \(age)s 未更新")
        }
        // 4. 手机靠近
        guard state.phoneNearby else {
            return .deny(action: .unlock, reason: "手机未进入解锁范围")
        }
        // 5. 车辆已锁
        guard state.locked == true else {
            return .deny(action: .unlock, reason: "车辆未上锁，无需重复解锁")
        }
        // 6. 车速 = 0
        if let speed = state.speed, speed > 0 {
            return .deny(action: .unlock, reason: "车辆行驶中 (\(Int(speed))km/h)")
        }
        // 7. 档位必须 P（安全底线，不可关闭）
        guard state.gear == .p else {
            return .deny(action: .unlock, reason: "档位 \(state.gear.title)，不允许无感解锁")
        }
        // 8. 电源熄火
        guard state.power == .off || state.power == .unknown else {
            return .deny(action: .unlock, reason: "车辆未熄火 (\(state.power.title))")
        }

        return .allow(action: .unlock, reason: "满足无感解锁条件")
    }

    // MARK: - 上锁评估
    static func evaluateLock(
        state: VehicleState,
        settings: KeylessSettings
    ) -> KeylessDecision {
        // 1. 无感总开关
        guard settings.keylessEnabled else {
            return .deny(action: .lock, reason: "无感开关关闭")
        }
        // 2. 上锁开关
        guard settings.lockEnabled else {
            return .deny(action: .lock, reason: "上锁开关关闭")
        }
        // 3. 状态新鲜度
        guard state.online else {
            return .deny(action: .lock, reason: "车辆离线")
        }
        guard state.isFresh() else {
            let age = Int(Date().timeIntervalSince(state.timestamp))
            return .deny(action: .lock, reason: "车辆状态 \(age)s 未更新")
        }
        // 4. 手机远离
        guard state.phoneFarAway else {
            return .deny(action: .lock, reason: "手机未离开上锁范围")
        }
        // 5. 车辆未锁
        guard state.locked == false else {
            return .deny(action: .lock, reason: "车辆已上锁，无需重复上锁")
        }
        // 6. 所有车门关闭
        if state.doorsClosed == false {
            return .deny(action: .lock, reason: "车门未关闭")
        }
        if state.driverDoorOpen == true {
            return .deny(action: .lock, reason: "主驾门未关闭")
        }
        // 7. 后备箱关闭
        if state.trunkOpen == true {
            return .deny(action: .lock, reason: "后备箱未关闭")
        }
        // 8. 车速 = 0
        if let speed = state.speed, speed > 0 {
            return .deny(action: .lock, reason: "车辆行驶中 (\(Int(speed))km/h)")
        }
        // 9. 档位必须 P（安全底线，不可关闭）
        guard state.gear == .p else {
            return .deny(action: .lock, reason: "档位 \(state.gear.title)，不允许无感上锁")
        }
        // 10. 电源熄火
        guard state.power == .off || state.power == .unknown else {
            return .deny(action: .lock, reason: "车辆未熄火 (\(state.power.title))")
        }
        // 11. 物理钥匙不在车内
        if state.physicalKeyInside == true {
            return .deny(action: .lock, reason: "物理钥匙在车内")
        }

        return .allow(action: .lock, reason: "满足无感上锁条件")
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

        if state.online {
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
            if let key = state.physicalKeyInside {
                parts.append("keyInside=\(key)")
            }
        } else {
            parts.append("offline")
        }

        return parts.joined(separator: " | ")
    }

    // MARK: - 评估 + 日志（一步到位）
    /// 评估解锁并写入日志
    @discardableResult
    static func evaluateAndLog(
        unlock state: VehicleState,
        settings: KeylessSettings,
        log: VehicleEventLogStore
    ) -> KeylessDecision {
        let decision = evaluateUnlock(state: state, settings: settings)
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
        log: VehicleEventLogStore
    ) -> KeylessDecision {
        let decision = evaluateLock(state: state, settings: settings)
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
