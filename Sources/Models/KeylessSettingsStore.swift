import SwiftUI
import Combine

// MARK: - 无感车控设置数据模型
struct KeylessSettings: Codable {
    // 无感功能
    var keylessEnabled: Bool = true
    /// 兼容旧存档；UI 已移除「插件托管」，自动化不再依赖此开关
    var pluginTakeover: Bool = true
    var smartSwitch: Bool = false
    var appManual: Bool = false
    var cmdInterval: Double = 5

    // 连接与操作确认
    /// MQTT 可选增强通道：关后不连接、不接收，状态胶囊隐藏。默认开。
    var mqttEnabled: Bool = true
    /// 快捷锁车/解锁是否显示二次确认。默认开；其他车控确认不受影响。
    var lockUnlockConfirmationEnabled: Bool = true

    // 解锁
    var unlockEnabled: Bool = true
    /// 无感靠近时发 BLE 启动电源（powerOnReady），替代无感解锁
    var powerStartEnabled: Bool = false
    var unlockThreshold: Double = -85
    var unlockApproachDuration: Double = 0
    var unlockPopup: Bool = true
    var unlockVibrate: Bool = true
    var unlockVibPreset: String = "shortSingle"
    var unlockVibCustomID: String? = nil
    var unlockVibStrength: Double = 60

    // 上锁
    var lockEnabled: Bool = true
    var lockThreshold: Double = -90
    var lockDelay: Double = 0
    var lockPopup: Bool = true
    var lockVibrate: Bool = true
    var lockVibPreset: String = "shortSingle"
    var lockVibCustomID: String? = nil
    var lockVibStrength: Double = 60

    // BLE 扫描
    var bleScanDuration: Double = 20
    var bleScanInterval: Double = 0

    // MARK: - 后台增强（设置页折叠组）
    /// 设置页「后台增强」是否展开（纯 UI）
    var backgroundSectionExpanded: Bool = false
    /// 增强后台执行
    var backgroundEnhancedEnabled: Bool = true
    /// 电子围栏预唤醒
    var geofenceWakeEnabled: Bool = true
    /// 围栏半径（米）50...500，默认 100；关围栏时隐藏滑块但不重置
    var geofenceRadiusMeters: Double = 100
    /// 仅围栏内扫描：开=圈外几乎不扫，进圈才扫；关=保持现状周期扫。默认关。前台+后台统一。
    var scanOnlyInsideGeofence: Bool = false
    /// 定位保活（按需）
    var locationKeepAliveEnabled: Bool = true
    /// 后台状态同步
    var backgroundStateSyncEnabled: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case keylessEnabled, pluginTakeover, smartSwitch, appManual, cmdInterval
        case mqttEnabled, lockUnlockConfirmationEnabled
        case unlockEnabled, powerStartEnabled, unlockThreshold, unlockApproachDuration, unlockPopup, unlockVibrate, unlockVibPreset, unlockVibCustomID, unlockVibStrength
        case lockEnabled, lockThreshold, lockDelay, lockPopup, lockVibrate, lockVibPreset, lockVibCustomID, lockVibStrength
        case bleScanDuration, bleScanInterval
        case backgroundSectionExpanded
        case backgroundEnhancedEnabled, geofenceWakeEnabled, geofenceRadiusMeters
        case scanOnlyInsideGeofence
        case locationKeepAliveEnabled, backgroundStateSyncEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keylessEnabled = try c.decodeIfPresent(Bool.self, forKey: .keylessEnabled) ?? true
        pluginTakeover = try c.decodeIfPresent(Bool.self, forKey: .pluginTakeover) ?? true
        smartSwitch = try c.decodeIfPresent(Bool.self, forKey: .smartSwitch) ?? false
        appManual = try c.decodeIfPresent(Bool.self, forKey: .appManual) ?? false
        cmdInterval = try c.decodeIfPresent(Double.self, forKey: .cmdInterval) ?? 5
        mqttEnabled = try c.decodeIfPresent(Bool.self, forKey: .mqttEnabled) ?? true
        lockUnlockConfirmationEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockUnlockConfirmationEnabled) ?? true

        unlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .unlockEnabled) ?? true
        powerStartEnabled = try c.decodeIfPresent(Bool.self, forKey: .powerStartEnabled) ?? false
        unlockThreshold = try c.decodeIfPresent(Double.self, forKey: .unlockThreshold) ?? -85
        unlockApproachDuration = try c.decodeIfPresent(Double.self, forKey: .unlockApproachDuration) ?? 0
        unlockPopup = try c.decodeIfPresent(Bool.self, forKey: .unlockPopup) ?? true
        unlockVibrate = try c.decodeIfPresent(Bool.self, forKey: .unlockVibrate) ?? true
        unlockVibPreset = try c.decodeIfPresent(String.self, forKey: .unlockVibPreset) ?? "shortSingle"
        unlockVibCustomID = try c.decodeIfPresent(String.self, forKey: .unlockVibCustomID)
        unlockVibStrength = try c.decodeIfPresent(Double.self, forKey: .unlockVibStrength) ?? 60

        lockEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockEnabled) ?? true
        lockThreshold = try c.decodeIfPresent(Double.self, forKey: .lockThreshold) ?? -90
        lockDelay = try c.decodeIfPresent(Double.self, forKey: .lockDelay) ?? 0
        lockPopup = try c.decodeIfPresent(Bool.self, forKey: .lockPopup) ?? true
        lockVibrate = try c.decodeIfPresent(Bool.self, forKey: .lockVibrate) ?? true
        lockVibPreset = try c.decodeIfPresent(String.self, forKey: .lockVibPreset) ?? "shortSingle"
        lockVibCustomID = try c.decodeIfPresent(String.self, forKey: .lockVibCustomID)
        lockVibStrength = try c.decodeIfPresent(Double.self, forKey: .lockVibStrength) ?? 60

        bleScanDuration = try c.decodeIfPresent(Double.self, forKey: .bleScanDuration) ?? 20
        bleScanInterval = try c.decodeIfPresent(Double.self, forKey: .bleScanInterval) ?? 0

        // 老用户升级只补默认值，不重置原有无感设置
        backgroundSectionExpanded = try c.decodeIfPresent(Bool.self, forKey: .backgroundSectionExpanded) ?? false
        backgroundEnhancedEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnhancedEnabled) ?? true
        geofenceWakeEnabled = try c.decodeIfPresent(Bool.self, forKey: .geofenceWakeEnabled) ?? true
        let rawRadius = try c.decodeIfPresent(Double.self, forKey: .geofenceRadiusMeters) ?? 100
        geofenceRadiusMeters = Self.clampedGeofenceRadius(rawRadius)
        scanOnlyInsideGeofence = try c.decodeIfPresent(Bool.self, forKey: .scanOnlyInsideGeofence) ?? false
        locationKeepAliveEnabled = try c.decodeIfPresent(Bool.self, forKey: .locationKeepAliveEnabled) ?? true
        backgroundStateSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundStateSyncEnabled) ?? true
    }

    static func clampedGeofenceRadius(_ value: Double) -> Double {
        let stepped = (value / 10.0).rounded() * 10.0
        return min(500, max(50, stepped))
    }

    /// 折叠标题摘要
    func backgroundEnhancementSummary(keylessEnabled: Bool) -> String {
        if !keylessEnabled { return "随无感停用" }
        let flags = [
            backgroundEnhancedEnabled,
            geofenceWakeEnabled,
            scanOnlyInsideGeofence,
            locationKeepAliveEnabled,
            backgroundStateSyncEnabled
        ]
        let onCount = flags.filter { $0 }.count
        if onCount == 0 { return "已关闭" }
        // 仅围栏扫描默认关，不算“全开”
        let coreFlags = [
            backgroundEnhancedEnabled,
            geofenceWakeEnabled,
            locationKeepAliveEnabled,
            backgroundStateSyncEnabled
        ]
        if coreFlags.allSatisfy({ $0 }) && !scanOnlyInsideGeofence { return "已开启" }
        if coreFlags.allSatisfy({ $0 }) && scanOnlyInsideGeofence { return "已开启·省电扫" }
        return "部分开启"
    }
}

// MARK: - 设置存储管理器
class KeylessSettingsStore: ObservableObject {
    static let shared = KeylessSettingsStore()

    @Published var settings = KeylessSettings() {
        didSet {
            // 半径硬裁剪
            let clamped = KeylessSettings.clampedGeofenceRadius(settings.geofenceRadiusMeters)
            if settings.geofenceRadiusMeters != clamped {
                settings.geofenceRadiusMeters = clamped
                return
            }
            save()
            // BackgroundExecutionManager 自行观察 $settings 并即时应用
        }
    }

    private let key = "KeylessSettings"

    init() {
        load()
    }

    // MARK: - 震动选择便捷方法

    func unlockVibChoice() -> VibrationChoice {
        if let customID = settings.unlockVibCustomID,
           let uuid = UUID(uuidString: customID) {
            return .custom(uuid)
        }
        if let preset = VibrationPattern(rawValue: settings.unlockVibPreset) {
            return .preset(preset)
        }
        return .preset(.shortSingle)
    }

    func setUnlockVibChoice(_ choice: VibrationChoice) {
        switch choice {
        case .preset(let p):
            settings.unlockVibPreset = p.rawValue
            settings.unlockVibCustomID = nil
        case .custom(let id):
            settings.unlockVibCustomID = id.uuidString
        }
    }

    func lockVibChoice() -> VibrationChoice {
        if let customID = settings.lockVibCustomID,
           let uuid = UUID(uuidString: customID) {
            return .custom(uuid)
        }
        if let preset = VibrationPattern(rawValue: settings.lockVibPreset) {
            return .preset(preset)
        }
        return .preset(.shortSingle)
    }

    func setLockVibChoice(_ choice: VibrationChoice) {
        switch choice {
        case .preset(let p):
            settings.lockVibPreset = p.rawValue
            settings.lockVibCustomID = nil
        case .custom(let id):
            settings.lockVibCustomID = id.uuidString
        }
    }

    func reset() {
        settings = KeylessSettings()
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(KeylessSettings.self, from: data) else { return }
        settings = decoded
    }
}
