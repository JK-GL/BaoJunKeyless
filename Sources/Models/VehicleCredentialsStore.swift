import Foundation
import Combine

// MARK: - 车辆配置存储
// 手动填入凭据，替代自动读取 App Group（TrollStore 侧载无法访问）

final class VehicleCredentialsStore: ObservableObject {
    static let shared = VehicleCredentialsStore()

    @Published var accessToken: String {
        didSet { persistAccessToken(accessToken) }
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
        self.accessToken = Self.loadAccessToken()
        self.vin = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.vin) ?? ""
        self.phone = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.phone) ?? ""
        self.autoReadWulingToken = UserDefaults.standard.object(forKey: AppDefaultsKey.VehicleCredentials.autoReadWulingToken) as? Bool ?? true
        self.tokenSourceLabel = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.tokenSourceLabel) ?? ""
        self.tokenSourcePath = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.tokenSourcePath) ?? ""
    }

    private static func loadAccessToken() -> String {
        let service = AppDefaultsKey.Keychain.vehicleCredentialService
        let account = AppDefaultsKey.Keychain.accessTokenAccount
        if let secureToken = KeychainStringStore.read(service: service, account: account), !secureToken.isEmpty {
            UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.accessToken)
            return secureToken
        }

        let legacyToken = UserDefaults.standard.string(forKey: AppDefaultsKey.VehicleCredentials.accessToken) ?? ""
        guard !legacyToken.isEmpty else { return "" }
        if KeychainStringStore.write(legacyToken, service: service, account: account) {
            UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.accessToken)
        }
        return legacyToken
    }

    private func persistAccessToken(_ token: String) {
        let service = AppDefaultsKey.Keychain.vehicleCredentialService
        let account = AppDefaultsKey.Keychain.accessTokenAccount
        if token.isEmpty {
            KeychainStringStore.delete(service: service, account: account)
            UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.accessToken)
        } else if KeychainStringStore.write(token, service: service, account: account) {
            UserDefaults.standard.removeObject(forKey: AppDefaultsKey.VehicleCredentials.accessToken)
        }
    }

    func reset() {
        let currentVIN = vin
        let currentPhone = phone
        if currentVIN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VehicleBLEKeyCacheStore.clearLastActive()
        } else {
            VehicleBLEKeyCacheStore.clear(vin: currentVIN, phone: currentPhone)
        }
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
