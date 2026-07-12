import Foundation

/// 用车机 BLE RSSI 估算离车距离（地下停车场 GPS 漂移时优先用这个）。
/// 模型：log-distance path loss，按无感阈值粗标定：
/// unlock≈-48 dBm ≈ 1.5m，lock≈-72 dBm ≈ 8m。
enum BLEProximityDistanceEstimator {
    /// 1 米参考 RSSI（车机数字钥匙模块常见区间）
    static let measuredPowerAt1m: Double = -52
    /// 环境衰减系数（车周/地库略偏高）
    static let pathLossExponent: Double = 2.35
    /// 显示上限：再远就回落 GPS
    static let maxTrustedMeters: Double = 25

    static func meters(fromRSSI rssi: Int) -> Double? {
        // 异常 RSSI 丢弃
        guard rssi > -100, rssi < 0 else { return nil }
        // d = 10 ^ ((Tx - RSSI) / (10 * n))
        let ratio = (measuredPowerAt1m - Double(rssi)) / (10.0 * pathLossExponent)
        let meters = pow(10.0, ratio)
        // 近场钳制：强信号按贴车处理，避免 0.1m 抖动
        let clamped = min(max(meters, 0.3), maxTrustedMeters)
        return clamped
    }

    /// 文案：近处更细，远处取整
    static func displayText(meters: Double) -> String {
        if meters < 10 {
            return String(format: "距车辆 %.1f 米 · 蓝牙", meters)
        }
        return String(format: "距车辆 %.0f 米 · 蓝牙", meters)
    }
}
