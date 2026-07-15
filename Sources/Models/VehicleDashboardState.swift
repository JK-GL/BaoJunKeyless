import Foundation
import SwiftUI

enum VehicleEnergyType: Equatable {
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
    var driverDoorStatusText: String = "--"
    var passengerDoorStatusText: String = "--"
    var leftRearDoorStatusText: String = "--"
    var rightRearDoorStatusText: String = "--"
    var leftFrontWindowStatusText: String = "--"
    var rightFrontWindowStatusText: String = "--"
    var leftRearWindowStatusText: String = "--"
    var rightRearWindowStatusText: String = "--"

    // 行驶 / 能耗
    var averageFuelConsumptionText: String = "--"
    var averagePowerConsumptionText: String = "--"
    var averageSpeedText: String = "--"
    var totalMileageText: String = "--"
    var yesterdayMileageText: String = "--"
    var fuelRemainingText: String = "--"

    var bodyStatusNormalText: String {
        let statuses = [
            lockStatusText, doorStatusText, windowStatusText, tailgateStatusText,
            driverDoorStatusText, passengerDoorStatusText, leftRearDoorStatusText, rightRearDoorStatusText,
            leftFrontWindowStatusText, rightFrontWindowStatusText, leftRearWindowStatusText, rightRearWindowStatusText
        ]
        // 离线缓存态不要显示成“异常”，避免把过期门窗当真
        if statuses.contains(where: { $0.contains("缓存") }) {
            return "缓存"
        }
        // 关键车身项均未知时，不能显示成“正常”。
        let known = statuses.filter { value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text != "--" && text != "未知"
        }
        if known.isEmpty { return "未知" }
        let badStatuses: [String] = ["未关", "未锁", "已开", "打开", "异常", "故障"]
        if known.contains(where: { badStatuses.contains($0) }) {
            return "异常"
        }
        let topLevel = [lockStatusText, doorStatusText, windowStatusText, tailgateStatusText]
        if topLevel.contains(where: {
            let text = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text == "--" || text == "未知"
        }) {
            return "部分未知"
        }
        return "正常"
    }

    var warningMessages: [String] {
        var warnings: [String] = []
        let badStatuses: [String] = ["未关", "未锁", "已开", "打开", "异常", "故障"]
        for (label, value) in [
            ("车锁", lockStatusText),
            ("尾门", tailgateStatusText),
            ("车门", doorStatusText),
            ("车窗", windowStatusText),
            ("主驾门", driverDoorStatusText),
            ("副驾门", passengerDoorStatusText),
            ("左后门", leftRearDoorStatusText),
            ("右后门", rightRearDoorStatusText),
            ("左前窗", leftFrontWindowStatusText),
            ("右前窗", rightFrontWindowStatusText),
            ("左后窗", leftRearWindowStatusText),
            ("右后窗", rightRearWindowStatusText)
        ] {
            // 缓存态不进“未关提醒”，避免离线误报一堆门窗异常
            if value.contains("缓存") { continue }
            if badStatuses.contains(value) {
                warnings.append("\(label)\(value)")
            }
        }
        return warnings
    }

    // 胎压
    var tireTemperatureText: String = "--"
    var leftFrontTirePressureText: String = "--"
    var rightFrontTirePressureText: String = "--"
    var leftRearTirePressureText: String = "--"
    var rightRearTirePressureText: String = "--"

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
    let tirePressure: [PopupStatusItem]
    let driving: [PopupStatusItem]
    let lighting: [PopupStatusItem]
}

enum StatusTint {
    static let infoBlue = Color(red: 0.42, green: 0.74, blue: 0.98)
    static let successGreen = Color(red: 0.40, green: 0.82, blue: 0.60)
    static let warningAmber = Color(red: 0.95, green: 0.72, blue: 0.35)
    static let dangerRed = Color(red: 0.95, green: 0.43, blue: 0.40)
    static let coolCyan = Color(red: 0.44, green: 0.88, blue: 0.92)
    static let muted = Color.white.opacity(0.45)
}

extension VehicleDashboardState {
    var metrics: VehicleDashboardMetrics {
        let closedColors = ["全关", "已关", "已锁", "已锁车"]
        let openColors = ["未关", "未锁", "已开", "打开", "异常", "故障"]

        func colorForStatus(_ status: String) -> Color {
            // “未锁·缓存”这类离线文案按缓存灰显，不当成实时异常红
            if status.contains("缓存") {
                return StatusTint.muted
            }
            if closedColors.contains(status) {
                return StatusTint.successGreen
            }
            if openColors.contains(status) {
                return StatusTint.dangerRed
            }
            return StatusTint.muted
        }

        return VehicleDashboardMetrics(
            battery: [
                PopupStatusItem(icon: "battery.100", label: "剩余", value: batteryRemainingText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "checkmark.seal.fill", label: "健康", value: batteryHealthPercentText, color: StatusTint.successGreen),
                PopupStatusItem(icon: "bolt.fill", label: "电压", value: batteryVoltageText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "battery.25", label: "小电瓶", value: batteryAuxText, color: StatusTint.infoBlue)
            ],
            temperature: [
                PopupStatusItem(icon: "thermometer", label: "车内", value: cabinTemperatureText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "snowflake", label: "空调", value: acTemperatureText, color: StatusTint.coolCyan),
                PopupStatusItem(icon: "thermometer", label: "电池", value: batteryTemperatureText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "gearshape.fill", label: "电机", value: motorTemperatureText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "cpu.fill", label: "逆变", value: inverterTemperatureText, color: StatusTint.warningAmber)
            ],
            charging: [
                PopupStatusItem(icon: "bolt.fill", label: "充电中", value: chargingStatusText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "gauge", label: "功率", value: chargingPowerValueText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "bolt.fill", label: "OBC电流", value: obcCurrentText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "thermometer", label: "OBC温度", value: obcTemperatureText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "bolt.circle.fill", label: "状态", value: chargingStateText, color: StatusTint.muted)
            ],
            bodyStatus: [
                PopupStatusItem(icon: "lock.fill", label: "车锁", value: lockStatusText, color: colorForStatus(lockStatusText)),
                PopupStatusItem(icon: "train.side.middle.car", label: "尾门", value: tailgateStatusText, color: colorForStatus(tailgateStatusText)),
                PopupStatusItem(icon: "train.side.front.car", label: "车门", value: doorStatusText, color: colorForStatus(doorStatusText)),
                PopupStatusItem(icon: "rectangle.split.3x1", label: "车窗", value: windowStatusText, color: colorForStatus(windowStatusText)),
                PopupStatusItem(icon: "train.side.front.car", label: "主驾门", value: driverDoorStatusText, color: colorForStatus(driverDoorStatusText)),
                PopupStatusItem(icon: "rectangle.split.3x1", label: "左前窗", value: leftFrontWindowStatusText, color: colorForStatus(leftFrontWindowStatusText)),
                PopupStatusItem(icon: "train.side.front.car", label: "副驾门", value: passengerDoorStatusText, color: colorForStatus(passengerDoorStatusText)),
                PopupStatusItem(icon: "rectangle.split.3x1", label: "右前窗", value: rightFrontWindowStatusText, color: colorForStatus(rightFrontWindowStatusText)),
                PopupStatusItem(icon: "train.side.front.car", label: "左后门", value: leftRearDoorStatusText, color: colorForStatus(leftRearDoorStatusText)),
                PopupStatusItem(icon: "rectangle.split.3x1", label: "左后窗", value: leftRearWindowStatusText, color: colorForStatus(leftRearWindowStatusText)),
                PopupStatusItem(icon: "train.side.front.car", label: "右后门", value: rightRearDoorStatusText, color: colorForStatus(rightRearDoorStatusText)),
                PopupStatusItem(icon: "rectangle.split.3x1", label: "右后窗", value: rightRearWindowStatusText, color: colorForStatus(rightRearWindowStatusText))
            ],
            tirePressure: [
                PopupStatusItem(icon: "circle.fill", label: "左前", value: leftFrontTirePressureText, color: leftFrontTirePressureText == "--" ? StatusTint.muted : StatusTint.infoBlue),
                PopupStatusItem(icon: "circle.fill", label: "右前", value: rightFrontTirePressureText, color: rightFrontTirePressureText == "--" ? StatusTint.muted : StatusTint.infoBlue),
                PopupStatusItem(icon: "circle.fill", label: "左后", value: leftRearTirePressureText, color: leftRearTirePressureText == "--" ? StatusTint.muted : StatusTint.infoBlue),
                PopupStatusItem(icon: "circle.fill", label: "右后", value: rightRearTirePressureText, color: rightRearTirePressureText == "--" ? StatusTint.muted : StatusTint.infoBlue)
            ],
            driving: [
                PopupStatusItem(icon: "scope", label: "方向盘", value: steeringAngleText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "arrow.up.circle.fill", label: "油门", value: throttlePercentText, color: StatusTint.successGreen),
                PopupStatusItem(icon: "stop.circle.fill", label: "刹车", value: brakePercentText, color: StatusTint.dangerRed),
                PopupStatusItem(icon: "speedometer", label: "实时车速", value: speedText, color: StatusTint.muted)
            ],
            lighting: [
                PopupStatusItem(icon: "lightbulb.fill", label: "近光灯", value: lowBeamText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "sun.max.fill", label: "远光灯", value: highBeamText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "arrow.left.arrow.right", label: "左转向", value: leftTurnText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "arrow.left.arrow.right", label: "右转向", value: rightTurnText, color: StatusTint.infoBlue),
                PopupStatusItem(icon: "sun.min.fill", label: "示宽灯", value: positionLightText, color: StatusTint.warningAmber),
                PopupStatusItem(icon: "cloud.fog", label: "前雾灯", value: frontFogText, color: StatusTint.warningAmber)
            ]
        )
    }
}
