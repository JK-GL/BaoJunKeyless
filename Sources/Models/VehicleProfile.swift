import Foundation

// MARK: - 车辆配置 / 能源检测
// 与灵宝win.js 逻辑对齐：capabilities → 文本关键词 → 油量信号 → 默认插混

enum DetectedEnergyType {
    case pureElectric
    case plugInHybrid
}

enum FuelBarMode: String, CaseIterable {
    case auto   // 自动识别
    case show   // 强制显示油量
    case hide   // 强制隐藏油量

    var label: String {
        switch self {
        case .auto: return "自动识别"
        case .show: return "强制显示"
        case .hide: return "强制隐藏"
        }
    }
}

struct VehicleCapabilities {
    var hasFuel: Bool? = nil
    var supportHybridMileage: Bool = false
    var supportBatteryIndicate: Bool = false
    var supportChargePower: Bool = false
}

struct VehicleProfile {
    var vin: String = ""
    var modelName: String = ""
    var carTypeName: String = ""

    // 能源类型字段
    var energyType: String = ""
    var powerType: String = ""
    var engineType: String = ""
    var vehicleType: String = ""
    var driveType: String = ""
    var fuelType: String = ""

    // 能力字段
    var capabilities: VehicleCapabilities = VehicleCapabilities()

    // MARK: - 能源类型检测（与灵宝win.js detectFuelSupport 逻辑一致）

    /// 检测是否为纯电：false = 纯电，true = 有油（插混/燃油）
    func detectHasFuel(fuelBarMode: FuelBarMode = .auto, status: VehicleState = .placeholder) -> Bool {
        // 优先级 1：手动覆盖
        switch fuelBarMode {
        case .show: return true
        case .hide: return false
        case .auto: break
        }

        // 优先级 2：能力字段
        if let hasFuel = capabilities.hasFuel {
            return hasFuel
        }

        // 优先级 3：文本关键词识别
        let text = [
            energyType, powerType, engineType, vehicleType,
            driveType, fuelType, carTypeName, modelName
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "|")
        .lowercased()

        let evKeywords = ["纯电", "电动", "ev", "bev"]
        let fuelKeywords = ["混动", "插混", "增程", "燃油", "汽油", "柴油", "phev", "hev", "reev", "hybrid"]

        let hasEvHint = evKeywords.contains { text.contains($0) }
        let hasFuelHint = fuelKeywords.contains { text.contains($0) }

        if hasEvHint && !hasFuelHint { return false }
        if hasFuelHint { return true }

        // 优先级 4：油量信号字段
        let fuelSignals: [Double?] = [
            status.fuelRange,
            status.fuelLevel,
            status.oilRange
        ]
        if fuelSignals.contains(where: { $0 != nil && $0! > 0 }) {
            return true
        }

        // 默认：有油（保守策略，和 JS 一致）
        return true
    }

    /// 快捷方法：检测能源类型
    func detectEnergyType(fuelBarMode: FuelBarMode = .auto, status: VehicleState = .placeholder) -> DetectedEnergyType {
        detectHasFuel(fuelBarMode: fuelBarMode, status: status) ? .plugInHybrid : .pureElectric
    }
}
