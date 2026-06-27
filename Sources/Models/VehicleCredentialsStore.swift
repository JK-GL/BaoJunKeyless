import Foundation
import Combine

// MARK: - 车辆配置存储
// 手动填入凭据，替代自动读取 App Group（TrollStore 侧载无法访问）

final class VehicleCredentialsStore: ObservableObject {
    @Published var accessToken: String {
        didSet { UserDefaults.standard.set(accessToken, forKey: key_token) }
    }
    @Published var vin: String {
        didSet { UserDefaults.standard.set(vin, forKey: key_vin) }
    }
    @Published var phone: String {
        didSet { UserDefaults.standard.set(phone, forKey: key_phone) }
    }
    @Published var autoReadWulingToken: Bool {
        didSet { UserDefaults.standard.set(autoReadWulingToken, forKey: key_autoReadWulingToken) }
    }
    @Published var tokenSourceLabel: String {
        didSet { UserDefaults.standard.set(tokenSourceLabel, forKey: key_tokenSourceLabel) }
    }
    @Published var tokenSourcePath: String {
        didSet { UserDefaults.standard.set(tokenSourcePath, forKey: key_tokenSourcePath) }
    }

    private let key_token = "VehicleCredentials.accessToken"
    private let key_vin = "VehicleCredentials.vin"
    private let key_phone = "VehicleCredentials.phone"
    private let key_autoReadWulingToken = "VehicleCredentials.autoReadWulingToken"
    private let key_tokenSourceLabel = "VehicleCredentials.tokenSourceLabel"
    private let key_tokenSourcePath = "VehicleCredentials.tokenSourcePath"

    var isConfigured: Bool {
        !accessToken.isEmpty && !vin.isEmpty
    }

    init() {
        self.accessToken = UserDefaults.standard.string(forKey: key_token) ?? ""
        self.vin = UserDefaults.standard.string(forKey: key_vin) ?? ""
        self.phone = UserDefaults.standard.string(forKey: key_phone) ?? ""
        self.autoReadWulingToken = UserDefaults.standard.object(forKey: key_autoReadWulingToken) as? Bool ?? true
        self.tokenSourceLabel = UserDefaults.standard.string(forKey: key_tokenSourceLabel) ?? ""
        self.tokenSourcePath = UserDefaults.standard.string(forKey: key_tokenSourcePath) ?? ""
    }

    func reset() {
        accessToken = ""
        vin = ""
        phone = ""
        tokenSourceLabel = ""
        tokenSourcePath = ""
        UserDefaults.standard.removeObject(forKey: key_token)
        UserDefaults.standard.removeObject(forKey: key_vin)
        UserDefaults.standard.removeObject(forKey: key_phone)
        UserDefaults.standard.removeObject(forKey: key_tokenSourceLabel)
        UserDefaults.standard.removeObject(forKey: key_tokenSourcePath)
    }
}
