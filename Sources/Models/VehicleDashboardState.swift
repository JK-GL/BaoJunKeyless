import Foundation
import SwiftUI

enum VehicleEnergyType {
    case plugInHybrid
    case pureElectric
}

struct VehicleDashboardState {
    var updatedAt: Date = Date()
    var vehicleName: String = ""
    var vehicleImageURL: String = ""
    var vinText: String = "--"
    var userIdText: String = "--"
    var bleMacText: String = "--"
    var keyIdText: String = "--"
    var masterKeyMaskedText: String = "--"
    var randomMaskedText: String = "--"
    var keyTypeText: String = "--"
    var keyExpiryText: String = "--"
    var vehicleInfoUpdatedAtText: String = "--"

    // 能源
    var energyType: VehicleEnergyType = .plugInHybrid
    var electricRangeKm: Int = 0
    var electricFullRangeKm: Int = 0
    var fuelRangeKm: Int = 0
    var fuelFullRangeKm: Int = 0
    var batteryPercentValue: Int? = nil
    var fuelPercentValue: Int? = nil
    var isCharging: Bool = false
    var chargingPowerText: String = "--"
    var updatedAtText: String = "--"

    // 电池
    var batteryRemainingText: String = "--"
    var batteryHealthPercentText: String = "--"
    var batteryVoltageText: String = "--"
    var batteryAuxText: String = "--"

    // 温度
    var cabinTemperatureText: String = "--"
    var acTemperatureText: String = "--"
    var batteryTemperatureText: String = "--"
    var motorTemperatureText: String = "--"
    var inverterTemperatureText: String = "--"

    // 充电
    var chargingStatusText: String = "--"
    var chargingPowerValueText: String = "--"
    var obcCurrentText: String = "--"
    var obcTemperatureText: String = "--"
    var chargingStateText: String = "--"

    // 车身状态
    var lockStatusText: String = "--"
    var doorStatusText: String = "--"
    var windowStatusText: String = "--"
    var tailgateStatusText: String = "--"

    // 行驶 / 能耗
    var averageFuelConsumptionText: String = "--"
    var averagePowerConsumptionText: String = "--"
    var averageSpeedText: String = "--"
    var totalMileageText: String = "--"
    var yesterdayMileageText: String = "--"
    var fuelRemainingText: String = "--"

    var bodyStatusNormalText: String {
        let badStatuses: [String] = ["未关", "未锁", "已开", "打开", "异常", "故障"]
        let statuses = [lockStatusText, doorStatusText, windowStatusText, tailgateStatusText]
        if statuses.contains(where: { badStatuses.contains($0) }) {
            return "异常"
        }
        return "正常"
    }

    var warningMessages: [String] {
        var warnings: [String] = []
        let badStatuses: [String] = ["未关", "未锁", "已开", "打开", "异常", "故障"]
        for (label, value) in [
            ("车锁", lockStatusText),
            ("车门", doorStatusText),
            ("车窗", windowStatusText),
            ("尾门", tailgateStatusText)
        ] {
            if badStatuses.contains(value) {
                warnings.append("\(label)\(value)")
            }
        }
        return warnings
    }

    // 驾驶
    var steeringAngleText: String = "--"
    var throttlePercentText: String = "--"
    var brakePercentText: String = "--"
    var speedText: String = "--"

    // 灯光
    var lowBeamText: String = "--"
    var highBeamText: String = "--"
    var leftTurnText: String = "--"
    var rightTurnText: String = "--"
    var positionLightText: String = "--"
    var frontFogText: String = "--"
}

struct VehicleDashboardMetrics {
    let battery: [PopupStatusItem]
    let temperature: [PopupStatusItem]
    let charging: [PopupStatusItem]
    let bodyStatus: [PopupStatusItem]
    let driving: [PopupStatusItem]
    let lighting: [PopupStatusItem]
}

extension VehicleDashboardState {
    var metrics: VehicleDashboardMetrics {
        let closedColors = ["全关", "已锁", "已锁车"]
        let openColors = ["未关", "未锁", "已开", "打开", "异常", "故障"]

        func colorForStatus(_ status: String) -> Color {
            if closedColors.contains(status) {
                return AppTheme.green
            }
            if openColors.contains(status) {
                return AppTheme.red
            }
            return Color.white.opacity(0.45)
        }

        return VehicleDashboardMetrics(
            battery: [
                PopupStatusItem(icon: "battery.100.bolt", label: "剩余", value: batteryRemainingText, color: AppTheme.accent),
                PopupStatusItem(icon: "checkmark.seal.fill", label: "健康", value: batteryHealthPercentText, color: AppTheme.green),
                PopupStatusItem(icon: "bolt.fill", label: "电压", value: batteryVoltageText, color: AppTheme.accent),
                PopupStatusItem(icon: "car.fill", label: "小电瓶", value: batteryAuxText, color: AppTheme.accent)
            ],
            temperature: [
                PopupStatusItem(icon: "thermometer", label: "车内", value: cabinTemperatureText, color: AppTheme.accent),
                PopupStatusItem(icon: "snowflake", label: "空调", value: acTemperatureText, color: AppTheme.orange),
                PopupStatusItem(icon: "thermometer.medium", label: "电池", value: batteryTemperatureText, color: AppTheme.green),
                PopupStatusItem(icon: "gearshape.fill", label: "电机", value: motorTemperatureText, color: AppTheme.green),
                PopupStatusItem(icon: "cpu.fill", label: "逆变", value: inverterTemperatureText, color: AppTheme.green)
            ],
            charging: [
                PopupStatusItem(icon: "bolt.fill", label: "充电中", value: chargingStatusText, color: AppTheme.orange),
                PopupStatusItem(icon: "gauge.medium", label: "功率", value: chargingPowerValueText, color: Color.white.opacity(0.45)),
                PopupStatusItem(icon: "bolt.fill", label: "OBC电流", value: obcCurrentText, color: AppTheme.orange),
                PopupStatusItem(icon: "thermometer", label: "OBC温度", value: obcTemperatureText, color: Color.white.opacity(0.45)),
                PopupStatusItem(icon: "bolt.circle.fill", label: "状态", value: chargingStateText, color: Color.white.opacity(0.45))
            ],
            bodyStatus: [
                PopupStatusItem(icon: "lock.fill", label: "车锁", value: lockStatusText, color: colorForStatus(lockStatusText)),
                PopupStatusItem(icon: "car.fill", label: "车门", value: doorStatusText, color: colorForStatus(doorStatusText)),
                PopupStatusItem(icon: "rectangle.split.2x2.fill", label: "车窗", value: windowStatusText, color: colorForStatus(windowStatusText)),
                PopupStatusItem(icon: "lock.fill", label: "尾门", value: tailgateStatusText, color: colorForStatus(tailgateStatusText))
            ],
            driving: [
                PopupStatusItem(icon: "scope", label: "方向盘", value: steeringAngleText, color: AppTheme.accent),
                PopupStatusItem(icon: "arrow.up.circle.fill", label: "油门", value: throttlePercentText, color: AppTheme.green),
                PopupStatusItem(icon: "stop.circle.fill", label: "刹车", value: brakePercentText, color: AppTheme.green),
                PopupStatusItem(icon: "speedometer", label: "平均车速", value: averageSpeedText, color: Color.white.opacity(0.45))
            ],
            lighting: [
                PopupStatusItem(icon: "lightbulb.fill", label: "近光灯", value: lowBeamText, color: AppTheme.orange),
                PopupStatusItem(icon: "sun.max.fill", label: "远光灯", value: highBeamText, color: AppTheme.orange),
                PopupStatusItem(icon: "arrow.left.arrow.right", label: "左转向", value: leftTurnText, color: AppTheme.accent),
                PopupStatusItem(icon: "arrow.left.arrow.right", label: "右转向", value: rightTurnText, color: AppTheme.accent),
                PopupStatusItem(icon: "sun.min.fill", label: "示宽灯", value: positionLightText, color: AppTheme.orange),
                PopupStatusItem(icon: "cloud.fog", label: "前雾灯", value: frontFogText, color: AppTheme.orange)
            ]
        )
    }
}
