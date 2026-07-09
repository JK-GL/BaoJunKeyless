import SwiftUI
import Combine

// MARK: - 无感车控设置数据模型
struct KeylessSettings: Codable {
    // 无感功能
    var keylessEnabled: Bool = true
    var pluginTakeover: Bool = true
    var smartSwitch: Bool = false
    var appManual: Bool = false
    var cmdInterval: Double = 5

    // 解锁
    var unlockEnabled: Bool = true
    var unlockThreshold: Double = -48
    var unlockApproachDuration: Double = 2
    var unlockPopup: Bool = true
    var unlockVibrate: Bool = true
    var unlockVibPreset: String = "shortSingle"
    var unlockVibCustomID: String? = nil
    var unlockVibStrength: Double = 60

    // 上锁
    var lockEnabled: Bool = true
    var lockThreshold: Double = -72
    var lockDelay: Double = 15
    var lockPopup: Bool = true
    var lockVibrate: Bool = true
    var lockVibPreset: String = "shortSingle"
    var lockVibCustomID: String? = nil
    var lockVibStrength: Double = 60

    // BLE 扫描
    var bleScanDuration: Double = 20
}

// MARK: - 设置存储管理器
class KeylessSettingsStore: ObservableObject {
    static let shared = KeylessSettingsStore()

    @Published var settings = KeylessSettings() {
        didSet { save() }
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
