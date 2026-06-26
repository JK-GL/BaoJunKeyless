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

    private let key_token = "VehicleCredentials.accessToken"
    private let key_vin = "VehicleCredentials.vin"
    private let key_phone = "VehicleCredentials.phone"

    var isConfigured: Bool {
        !accessToken.isEmpty && !vin.isEmpty
    }

    init() {
        self.accessToken = UserDefaults.standard.string(forKey: key_token) ?? ""
        self.vin = UserDefaults.standard.string(forKey: key_vin) ?? ""
        self.phone = UserDefaults.standard.string(forKey: key_phone) ?? ""
    }

    func reset() {
        accessToken = ""
        vin = ""
        phone = ""
        UserDefaults.standard.removeObject(forKey: key_token)
        UserDefaults.standard.removeObject(forKey: key_vin)
        UserDefaults.standard.removeObject(forKey: key_phone)
    }
}
