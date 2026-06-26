import Foundation
import CryptoKit

// MARK: - SGMW API 客户端
// 负责：读取本地 token、调用 base/mqtt/auth 获取 mqttToken、生成 MQTT 凭据

final class SGMWApiClient {
    static let shared = SGMWApiClient()

    // 固定配置（所有用户相同）
    private let clientId = "2019041810222516127"
    private let clientSecret = "c5ad2a4290faa3df39683865c2e10310"
    private let appCode = "sgmw_llb"
    private let baseUrl = "https://openapi.baojun.net/junApi/sgmw"

    private init() {}

    // MARK: - Token 读取

    /// 从本地读取 access_token
    /// TrollStore 侧载 App 有文件系统权限，可直接读取 App Group 容器
    func readLocalToken() -> String? {
        // 搜索路径列表（TrollStore 可能无法访问 App Group，优先搜 /var/mobile/）
        let searchPaths = [
            "/var/mobile/SavedOAuthModel",                          // 用户手动复制到这里
            "/var/mobile/Containers/Shared/AppGroup/group.com.cloudy.LingLingBang/SavedOAuthModel",
            "/private/var/mobile/Containers/Shared/AppGroup/group.com.cloudy.LingLingBang/SavedOAuthModel",
        ]

        // 额外搜索：遍历所有 App Group 容器
        let appGroupBases = [
            "/private/var/mobile/Containers/Shared/AppGroup",
            "/var/mobile/Containers/Shared/AppGroup",
        ]

        var allPaths = searchPaths
        for base in appGroupBases {
            if let containers = try? FileManager.default.contentsOfDirectory(atPath: base) {
                for container in containers {
                    allPaths.append("\(base)/\(container)/SavedOAuthModel")
                }
            }
        }

        CrashLogger.shared.mark("SGMW", "searching \(allPaths.count) paths")

        for path in allPaths {
            if FileManager.default.fileExists(atPath: path),
               let data = FileManager.default.contents(atPath: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String,
               !token.isEmpty {
                CrashLogger.shared.mark("SGMW", "token found from \(path)")
                return token
            }
        }

        CrashLogger.shared.mark("SGMW", "no token in any path")

        // 方案2: 标准 App Group API
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.cloudy.LingLingBang"
        ) {
            let path = url.appendingPathComponent("SavedOAuthModel")
            if let data = try? Data(contentsOf: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String,
               !token.isEmpty {
                CrashLogger.shared.mark("SGMW", "token found from App Group API")
                return token
            }
        }

        // 方案3: 宝骏 App plist
        let baojunPath = "/var/mobile/Library/Preferences/com.sgmw.baojunplus.plist"
        if FileManager.default.fileExists(atPath: baojunPath),
           let prefs = NSDictionary(contentsOfFile: baojunPath),
           let oauthStr = prefs["flutter.user_oauth"] as? String,
           let oauthData = oauthStr.data(using: .utf8),
           let oauth = try? JSONSerialization.jsonObject(with: oauthData) as? [String: Any],
           let token = oauth["access_token"] as? String,
           !token.isEmpty {
            CrashLogger.shared.mark("SGMW", "token found from Baojun plist")
            return token
        }

        CrashLogger.shared.mark("SGMW", "no token found in any location")
        return nil
    }

    /// 从本地读取 VIN 和手机号（SavedOAuthModel 可能包含，否则调 API）
    func readLocalVehicleInfo(token: String, completion: @escaping ((vin: String, phone: String)?) -> Void) {
        // 先尝试从 SavedOAuthModel 读取
        let appGroupBase = "/private/var/mobile/Containers/Shared/AppGroup"
        if let containers = try? FileManager.default.contentsOfDirectory(atPath: appGroupBase) {
            for container in containers {
                let savedPath = "\(appGroupBase)/\(container)/SavedOAuthModel"
                if let data = FileManager.default.contents(atPath: savedPath),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let vin = json["vin"] as? String, !vin.isEmpty,
                   let phone = json["phone"] as? String ?? json["mobile"] as? String {
                    completion((vin: vin, phone: phone))
                    return
                }
            }
        }

        // 本地没有，调 API 查询
        queryDefaultCar(accessToken: token, completion: completion)
    }

    // MARK: - API 调用

    /// 调用 API 获取 mqttToken
    func fetchMqttToken(accessToken: String, vin: String, phone: String, completion: @escaping (String?) -> Void) {
        let endpoint = "base/mqtt/auth"
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else {
            completion(nil)
            return
        }

        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let nonce = String((0..<10).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let signature = generateSignature(accessToken: accessToken, timestamp: timestamp, nonce: nonce)

        let headers: [String: String] = [
            "Content-Type": "application/json; charset=UTF-8",
            "User-Agent": "okhttp/4.9.0",
            "sgmwaccesstoken": accessToken,
            "sgmwtimestamp": timestamp,
            "sgmwnonce": nonce,
            "sgmwclientid": clientId,
            "sgmwclientsecret": clientSecret,
            "sgmwappcode": appCode,
            "sgmwappversion": "5.2.22",
            "sgmwsystem": "android",
            "sgmwsystemversion": "10",
            "sgmwsignature": signature
        ]

        let body = try? JSONSerialization.data(withJSONObject: ["vin": vin, "userId": phone])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? Bool, result,
                  let dataObj = json["data"] as? [String: Any],
                  let token = dataObj["mqttToken"] as? String else {
                completion(nil)
                return
            }
            completion(token)
        }.resume()
    }

    /// 查询默认车辆状态（获取 VIN + 手机号）
    func queryDefaultCar(accessToken: String, completion: @escaping ((vin: String, phone: String)?) -> Void) {
        let endpoint = "userCarRelation/queryDefaultCarStatus"
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else {
            completion(nil)
            return
        }

        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let nonce = String((0..<10).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let signature = generateSignature(accessToken: accessToken, timestamp: timestamp, nonce: nonce)

        let headers: [String: String] = [
            "Content-Type": "application/json; charset=UTF-8",
            "User-Agent": "okhttp/4.9.0",
            "sgmwaccesstoken": accessToken,
            "sgmwtimestamp": timestamp,
            "sgmwnonce": nonce,
            "sgmwclientid": clientId,
            "sgmwclientsecret": clientSecret,
            "sgmwappcode": appCode,
            "sgmwappversion": "5.2.22",
            "sgmwsystem": "android",
            "sgmwsystemversion": "10",
            "sgmwsignature": signature
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? Bool, result,
                  let dataObj = json["data"] as? [String: Any],
                  let carInfo = dataObj["carInfo"] as? [String: Any],
                  let vin = carInfo["vin"] as? String,
                  let phone = carInfo["bindCarUserMobile"] as? String else {
                completion(nil)
                return
            }
            completion((vin: vin, phone: phone))
        }.resume()
    }

    // MARK: - MQTT 凭据生成

    /// 根据 mqttToken 生成 MQTT 连接凭据
    struct MQTTCredentials {
        let broker: String
        let port: UInt16
        let username: String
        let password: String
        let clientId: String
        let vin: String
        let topics: [String]
    }

    func generateMQTTCredentials(vin: String, phone: String, mqttToken: String) -> MQTTCredentials {
        let randomSuffix = String(format: "%04d", Int.random(in: 0...9999))
        let clientId = "\(vin)_\(randomSuffix)"

        // Username = MD5(VIN前6位 + mqttToken)
        let usernameInput = String(vin.prefix(6)) + mqttToken
        let username = md5(usernameInput)

        // Password = MD5(ClientID后6位 + mqttToken)
        let passwordInput = String(clientId.suffix(6)) + mqttToken
        let password = md5(passwordInput)

        let topics = [
            "\(vin)/prod/sgmw/vehicle/app/status",
            "\(vin)/prod/sgmw/vehicle/control",
            "\(vin)/prod/sgmw/vehicle/car_check_authorize/business",
            "\(vin)/prod/sgmw/vehicle/car_parking_notify/business"
        ]

        return MQTTCredentials(
            broker: "parkingdata.sgmwcloud.com.cn",
            port: 1883,
            username: username,
            password: password,
            clientId: clientId,
            vin: vin,
            topics: topics
        )
    }

    // MARK: - 签名

    private func generateSignature(accessToken: String, timestamp: String, nonce: String) -> String {
        let signStr = accessToken + timestamp + nonce + clientId + clientSecret + appCode + "5.2.22" + "android" + "10"
        return SHA256.hash(data: Data(signStr.utf8)).map { String(format: "%02hhx", $0) }.joined()
    }

    private func md5(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
