import Foundation
import CryptoKit

// MARK: - SGMW API 客户端
// 负责：读取本地 token、调用 HTTP API、获取 mqttToken、生成 MQTT 凭据

final class SGMWApiClient {
    static let shared = SGMWApiClient()

    // 固定配置（所有用户相同）
    private let clientId = "2019041810222516127"
    private let clientSecret = "c5ad2a4290faa3df39683865c2e10310"
    private let appCode = "sgmw_llb"
    private let baseUrl = "https://openapi.baojun.net/junApi/sgmw"
    private let appVersion = "5.2.15"
    private let systemName = "iOS"
    private let systemVersion = "15.4.1"
    private let userAgent = "LingLingBang/5.2.15"

    private init() {}

    // MARK: - 类型

    struct VehicleDefaultCarInfo {
        let vin: String
        let phone: String
    }

    struct VehicleHTTPPayload {
        let carInfo: [String: String]
        let carStatus: [String: String]
    }

    struct MQTTCredentials {
        let broker: String
        let port: UInt16
        let username: String
        let password: String
        let clientId: String
        let vin: String
        let topics: [String]
    }

    // MARK: - Token 读取

    /// 从本地读取 access_token
    /// 主路径：/var/mobile/SavedOAuthModel（用户复制后最稳）
    /// 兜底：宝骏 app plist
    func readLocalToken() -> String? {
        let searchPaths = [
            "/var/mobile/SavedOAuthModel",
            "/private/var/mobile/SavedOAuthModel",
            "/var/mobile/Containers/Shared/AppGroup/group.com.cloudy.LingLingBang/SavedOAuthModel",
            "/private/var/mobile/Containers/Shared/AppGroup/group.com.cloudy.LingLingBang/SavedOAuthModel"
        ]

        CrashLogger.shared.mark("SGMW", "searching token in \(searchPaths.count) fixed paths")

        for path in searchPaths {
            if let token = readTokenFromJSONFile(path: path) {
                CrashLogger.shared.mark("SGMW", "token found from \(path)")
                return token
            }
        }

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

    private func readTokenFromJSONFile(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let token = json["access_token"] as? String, !token.isEmpty { return token }
        if let dataObj = json["data"] as? [String: Any], let token = dataObj["access_token"] as? String, !token.isEmpty { return token }
        return nil
    }

    // MARK: - HTTP API

    /// 查询默认车辆状态（拿 VIN + 手机号）
    func queryDefaultCar(accessToken: String, completion: @escaping (VehicleDefaultCarInfo?) -> Void) {
        apiCall(endpoint: "userCarRelation/queryDefaultCarStatus", body: [:], accessToken: accessToken) { json in
            guard let json,
                  let dataObj = json["data"] as? [String: Any],
                  let carInfo = dataObj["carInfo"] as? [String: Any],
                  let vin = self.stringValue(carInfo["vin"]), !vin.isEmpty,
                  let phone = self.stringValue(carInfo["bindCarUserMobile"]), !phone.isEmpty else {
                completion(nil)
                return
            }
            completion(VehicleDefaultCarInfo(vin: vin, phone: phone))
        }
    }

    /// 查询完整车辆状态（HTTP 基础状态）
    func queryVehicleStatus(accessToken: String, completion: @escaping (VehicleHTTPPayload?) -> Void) {
        apiCall(endpoint: "userCarRelation/queryDefaultCarStatus", body: [:], accessToken: accessToken) { json in
            guard let json,
                  let dataObj = json["data"] as? [String: Any] else {
                completion(nil)
                return
            }

            let carInfo = self.stringifyDictionary(dataObj["carInfo"] as? [String: Any] ?? [:])
            let carStatus = self.stringifyDictionary(dataObj["carStatus"] as? [String: Any] ?? [:])
            completion(VehicleHTTPPayload(carInfo: carInfo, carStatus: carStatus))
        }
    }

    /// 查询 BLE 钥匙信息（用于车辆信息卡）
    func queryBleKey(accessToken: String, vin: String, phone: String, completion: @escaping ([String: String]?) -> Void) {
        apiCall(
            endpoint: "car/control/ble/key/query",
            body: ["vin": vin, "userId": phone],
            accessToken: accessToken
        ) { json in
            guard let json,
                  let dataObj = json["data"] as? [String: Any] else {
                completion(nil)
                return
            }
            completion(self.stringifyDictionary(dataObj))
        }
    }

    /// 调用 API 获取 mqttToken
    func fetchMqttToken(accessToken: String, vin: String, completion: @escaping (String?) -> Void) {
        apiCall(endpoint: "base/mqtt/auth", body: ["vin": vin], accessToken: accessToken) { json in
            guard let json,
                  let dataObj = json["data"] as? [String: Any] else {
                completion(nil)
                return
            }
            let token = self.stringValue(dataObj["token"]) ?? self.stringValue(dataObj["mqttToken"])
            completion(token?.isEmpty == false ? token : nil)
        }
    }

    // MARK: - MQTT 凭据生成

    func generateMQTTCredentials(vin: String, phone: String, mqttToken: String) -> MQTTCredentials {
        let randomSuffix = String(format: "%04d", Int.random(in: 0...9999))
        let clientId = "\(vin)_\(randomSuffix)"

        let usernameInput = String(vin.prefix(6)) + mqttToken
        let passwordInput = String(clientId.suffix(6)) + mqttToken

        let topics = [
            "\(vin)/prod/sgmw/vehicle/app/status",
            "\(vin)/prod/sgmw/vehicle/control",
            "\(vin)/prod/sgmw/vehicle/car_check_authorize/business",
            "\(vin)/prod/sgmw/vehicle/car_parking_notify/business"
        ]

        return MQTTCredentials(
            broker: "parkingdata.sgmwcloud.com.cn",
            port: 1883,
            username: md5(usernameInput),
            password: md5(passwordInput),
            clientId: clientId,
            vin: vin,
            topics: topics
        )
    }

    // MARK: - 请求底层

    private func apiCall(endpoint: String, body: [String: Any], accessToken: String, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else {
            completion(nil)
            return
        }

        let headers = buildSignedHeaders(accessToken: accessToken)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.allHTTPHeaderFields = headers
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["result"] as? Bool) == true else {
                completion(nil)
                return
            }
            completion(json)
        }.resume()
    }

    private func buildSignedHeaders(accessToken: String) -> [String: String] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let nonce = String((0..<10).compactMap { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement() })
        let signature = generateSignature(accessToken: accessToken, timestamp: timestamp, nonce: nonce)

        return [
            "Content-Type": "application/json; charset=UTF-8",
            "User-Agent": userAgent,
            "sgmwaccesstoken": accessToken,
            "sgmwtimestamp": timestamp,
            "sgmwnonce": nonce,
            "sgmwclientid": clientId,
            "sgmwclientsecret": clientSecret,
            "sgmwappcode": appCode,
            "sgmwappversion": appVersion,
            "sgmwsystem": systemName,
            "sgmwsystemversion": systemVersion,
            "sgmwsignature": signature
        ]
    }

    // MARK: - 工具

    private func generateSignature(accessToken: String, timestamp: String, nonce: String) -> String {
        let signStr = accessToken + timestamp + nonce + clientId + clientSecret + appCode + appVersion + systemName + systemVersion
        return SHA256.hash(data: Data(signStr.utf8)).map { String(format: "%02hhx", $0) }.joined()
    }

    private func md5(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let i as Int: return String(i)
        case let d as Double: return String(d)
        default: return nil
        }
    }

    private func stringifyDictionary(_ dict: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in dict {
            if let string = stringValue(value), !string.isEmpty {
                result[key] = string
            }
        }
        return result
    }
}
