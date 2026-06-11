import Foundation
import SwiftUI

struct VehicleDashboardState {
    var updatedAt: Date = Date()

    // 能源
    var electricRangeKm: Int = 140
    var electricFullRangeKm: Int = 140
    var fuelRangeKm: Int = 680
    var fuelFullRangeKm: Int = 800
    var isCharging: Bool = false
    var chargingPowerText: String = "3.2 kW"

    // 电池
    var batteryRemainingText: String = "17.8kWh"
    var batteryHealthPercentText: String = "99%"
    var batteryVoltageText: String = "109.5V"
    var batteryAuxText: String = "12.4V"

    // 温度
    var cabinTemperatureText: String = "22°C"
    var acTemperatureText: String = "17°C"
    var batteryTemperatureText: String = "25°C"
    var motorTemperatureText: String = "27°C"
    var inverterTemperatureText: String = "27°C"

    // 充电
    var chargingStatusText: String = "否"
    var chargingPowerValueText: String = "--"
    var obcCurrentText: String = "0A"
    var obcTemperatureText: String = "--"
    var chargingStateText: String = "--"

    // 车身状态
    var lockStatusText: String = "已锁车"
    var doorStatusText: String = "全关"
    var windowStatusText: String = "全关"
    var tailgateStatusText: String = "已锁"

    var bodyStatusNormalText: String { "正常" }

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
    var steeringAngleText: String = "0.0°"
    var throttlePercentText: String = "0%"
    var brakePercentText: String = "0%"
    var speedText: String = "--"

    // 灯光
    var lowBeamText: String = "关闭"
    var highBeamText: String = "关闭"
    var leftTurnText: String = "关闭"
    var rightTurnText: String = "关闭"
    var positionLightText: String = "关闭"
    var frontFogText: String = "关闭"
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
        VehicleDashboardMetrics(
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
                PopupStatusItem(icon: "lock.fill", label: "车锁", value: lockStatusText, color: AppTheme.green),
                PopupStatusItem(icon: "car.fill", label: "车门", value: doorStatusText, color: AppTheme.green),
                PopupStatusItem(icon: "rectangle.fill", label: "车窗", value: windowStatusText, color: AppTheme.green),
                PopupStatusItem(icon: "lock.fill", label: "尾门", value: tailgateStatusText, color: AppTheme.green)
            ],
            driving: [
                PopupStatusItem(icon: "scope", label: "方向盘", value: steeringAngleText, color: AppTheme.accent),
                PopupStatusItem(icon: "arrow.up.circle.fill", label: "油门", value: throttlePercentText, color: AppTheme.green),
                PopupStatusItem(icon: "stop.circle.fill", label: "刹车", value: brakePercentText, color: AppTheme.green),
                PopupStatusItem(icon: "speedometer", label: "车速", value: speedText, color: Color.white.opacity(0.45))
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
