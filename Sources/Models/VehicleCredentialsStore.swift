import Foundation
import Combine

// MARK: - 车辆配置存储
// 手动填入凭据，替代自动读取 App Group（TrollStore 侧载无法访问）

final class VehicleCredentialsStore: ObservableObject {
    static let shared = VehicleCredentialsStore()

    @Published var accessToken: String {
        didSet { UserDefaults.standard.set(accessToken, forKey: AppDefaultsKey.VehicleCredentials.accessToken) }
    }
    @Published var vin: String {
        didSet { UserDefaults.standard.set(vin, forKey: AppDefaultsKey.VehicleCredentials.vin) }
    }
    @Published var phone: String {
        didSet { UserDefaults.standard.set(phone, forKey: AppDefaultsKey.VehicleCredentials.phone) }
    }
    @Published var autoReadWulingToken: Bool {
        didSet { UserDefaults.standard.set(autoReadWulingToken, forKey: AppDefaultsKey.VehicleCredentials.autoReadWulingToken) }
    }
    @Published var tokenSourceLabel: String {
        didSet { UserDefaults.standard.set(tokenSourceLabel, forKey: AppDefaultsKey.VehicleCredentials.tokenSourceLabel) }
    }
    @Published var tokenSourcePath: String {
        didSet { UserDefaults.standard.set(tokenSourcePath, forKey: AppDefaultsKey.VehicleCredentials.tokenSourcePath) }
    }

    var isConfigured: Bool {
        !accessToken.isEmpty && !vin.isEmpty
    }

    init() {
        self.accessToken = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.accessToken) ?? ""
        self.vin = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.vin) ?? ""
        self.phone = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.phone) ?? ""
        self.autoReadWulingToken = UserDefaults.standard.object(forKey: AppDefaultsKey.VehicleCredentials.autoReadWulingToken) as? Bool ?? true
        self.tokenSourceLabel = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.tokenSourceLabel) ?? ""
        self.tokenSourcePath = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.tokenSourcePath) ?? ""
    }

    func reset() {
        accessToken = ""
        vin = ""
        phone = ""
        tokenSourceLabel = ""
        tokenSourcePath = ""
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.accessToken)
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.vin)
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.phone)
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.tokenSourceLabel)
        UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.tokenSourcePath)
    }
}
