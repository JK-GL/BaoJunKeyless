import Foundation

// MARK: - 统一持久化 Key
// 说明：
// - 只收口本项目内部持久化 key
// - 与外部官方 App 本地 plist 对接时，复用同一组字符串，避免多处手写

enum AppDefaultsKey {
    enum Keychain {
        static let vehicleCredentialService = "com.baojun.keyless.vehicle-credentials"
        static let accessTokenAccount = "accessToken"
    }

    enum AddressService {
        static let amapWebKey = "AddressService.AmapWebKey"
    }

    enum VehicleCache {
        static let lastAddress = "LastAddress"
        static let lastLatitude = "LastLatitude"
        static let lastLongitude = "LastLongitude"
        static let lastDistanceMeters = "LastDistanceMeters"
        static let lastDistanceTimestamp = "LastDistanceTs"
    }

    enum VehicleCredentials {
        static let accessToken = "VehicleCredentials.accessToken"
        static let vin = "VehicleCredentials.vin"
        static let phone = "VehicleCredentials.phone"
        static let autoReadWulingToken = "VehicleCredentials.autoReadWulingToken"
        static let tokenSourceLabel = "VehicleCredentials.tokenSourceLabel"
        static let tokenSourcePath = "VehicleCredentials.tokenSourcePath"
    }

    enum CrashLogger {
        static let enabled = "CrashLoggerEnabled"
    }

    enum VehicleEventLog {
        static let entries = "VehicleEventLogs"
    }

    enum CustomVibration {
        static let patterns = "CustomVibrationPatterns"
    }
}
