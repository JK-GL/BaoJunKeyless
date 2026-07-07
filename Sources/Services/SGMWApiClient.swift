import Foundation
import CryptoKit

// MARK: - SGMW API 错误类型
enum SGMWApiError: LocalizedError {
    case invalidToken
    case invalidVIN
    case invalidPhone
    case network(Error?)
    case invalidResponse(String?)
    case serverMessage(String)
    case parseFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidToken: return "Token 已失效或未配置"
        case .invalidVIN: return "车架号无效"
        case .invalidPhone: return "手机号无效"
        case .network(let err): return "网络请求失败：\(err?.localizedDescription ?? "未知错误")"
        case .invalidResponse(let detail): return "服务器返回异常\(detail.map { "：\($0)" } ?? "")"
        case .serverMessage(let msg): return msg
        case .parseFailed(let detail): return "数据解析失败\(detail.map { "：\($0)" } ?? "")"
        }
    }
}

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

    struct VehicleControlRequestPlan {
        let command: VehicleCommandKind
        let endpointCandidates: [String]
        let bodyKeys: [String]
        let note: String
    }

    struct VehicleControlRequestDraft {
        let plan: VehicleControlRequestPlan
        let url: URL
        let headers: [String: String]
        let body: [String: Any]
    }

    // MARK: - Token 读取

    /// 从本地读取 access_token
    /// 主路径：/var/mobile/SavedOAuthModel（用户复制后最稳）
    /// 兜底：宝骏 app plist
    func readLocalToken() -> String? {
        if let tokenInfo = WulingAppCacheReader.shared.readTokenInfo() {
            CrashLogger.shared.mark("SGMW", "token found from \(tokenInfo.sourcePath)")
            return tokenInfo.token
        }

        CrashLogger.shared.mark("SGMW", "no Wuling token found")
        return nil
    }

    func readLocalTokenInfo() -> WulingAppCacheReader.TokenInfo? {
        WulingAppCacheReader.shared.readTokenInfo()
    }

    private func readTokenFromJSONFile(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let token = json["access_token"] as? String, !token.isEmpty { return token }
        if let dataObj = json["data"] as? [String: Any], let token = dataObj["access_token"] as? String, !token.isEmpty { return token }
        return nil
    }

    // MARK: - HTTP API

    /// 查询默认车辆状态（拿 VIN + 手机号 — Result 版本）
    func queryDefaultCarResult(accessToken: String, completion: @escaping (Result<VehicleDefaultCarInfo, SGMWApiError>) -> Void) {
        apiCallResult(endpoint: "userCarRelation/queryDefaultCarStatus", body: [:], accessToken: accessToken) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let json):
                guard let dataObj = json["data"] as? [String: Any],
                      let carInfo = dataObj["carInfo"] as? [String: Any],
                      let vin = self.stringValue(carInfo["vin"]), !vin.isEmpty,
                      let phone = self.stringValue(carInfo["bindCarUserMobile"]), !phone.isEmpty else {
                    completion(.failure(.parseFailed("缺少 VIN 或手机号")))
                    return
                }
                completion(.success(VehicleDefaultCarInfo(vin: vin, phone: phone)))
            }
        }
    }

    /// 查询完整车辆状态（HTTP 基础状态 — Result 版本）
    func queryVehicleStatusResult(accessToken: String, completion: @escaping (Result<VehicleHTTPPayload, SGMWApiError>) -> Void) {
        apiCallResult(endpoint: "userCarRelation/queryDefaultCarStatus", body: [:], accessToken: accessToken) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let json):
                guard let dataObj = json["data"] as? [String: Any] else {
                    completion(.failure(.parseFailed("缺少 data")))
                    return
                }
                let carInfo = self.stringifyDictionary(dataObj["carInfo"] as? [String: Any] ?? [:])
                let carStatus = self.stringifyDictionary(dataObj["carStatus"] as? [String: Any] ?? [:])
                completion(.success(VehicleHTTPPayload(carInfo: carInfo, carStatus: carStatus)))
            }
        }
    }

    /// 根据命令生成控制接口计划。
    /// 已按 /var/minis/shared/BLE_SPEC.md v7.1 收口云端控制 endpoint。
    func makeVehicleControlRequestPlan(for command: VehicleCommand) -> VehicleControlRequestPlan {
        switch command.kind {
        case .lock:
            return VehicleControlRequestPlan(command: .lock, endpointCandidates: ["car/control/doorLock"], bodyKeys: ["vin", "status"], note: "BLE_SPEC v7.1：门锁控制 status=1 锁车")
        case .unlock:
            return VehicleControlRequestPlan(command: .unlock, endpointCandidates: ["car/control/doorLock"], bodyKeys: ["vin", "status"], note: "BLE_SPEC v7.1：门锁控制 status=0 解锁")
        case .remoteStart:
            return VehicleControlRequestPlan(command: .remoteStart, endpointCandidates: ["car/control/ignition/authorize"], bodyKeys: ["vin"], note: "BLE_SPEC v7.1：远程启动第一步 PEPS 鉴权；后续 BLE CMD 仍待确认")
        case .remoteStop:
            return VehicleControlRequestPlan(command: .remoteStop, endpointCandidates: ["remote/V3/safety/sendVhlCtl"], bodyKeys: ["vin", "qgRemoteStopExtendedObjects"], note: "HTTP_BLE_CONTROL_DIG_RESULT：BLE 未连接时尝试 QG sendVhlCtl 一键关上电+关闭发动机")
        case .findCar:
            return VehicleControlRequestPlan(command: .findCar, endpointCandidates: ["car/control/searchCar"], bodyKeys: ["vin", "status"], note: "BLE_SPEC v7.1：寻车 status=0 双闪鸣笛")
        case .acOn:
            return VehicleControlRequestPlan(command: .acOn, endpointCandidates: ["car/control/acc"], bodyKeys: ["vin", "accOnOff", "status", "temperature"], note: "BLE_SPEC v7.1：空调 status=6 开空调，温度下限按快冷 17°C")
        case .acOff:
            return VehicleControlRequestPlan(command: .acOff, endpointCandidates: ["car/control/acc"], bodyKeys: ["vin", "accOnOff", "status"], note: "BLE_SPEC v7.1：空调 status=7 关空调")
        case .openWindows:
            return VehicleControlRequestPlan(command: .openWindows, endpointCandidates: ["car/control/window"], bodyKeys: ["vin", "status"], note: "BLE_SPEC v7.1：车窗 status=0 开车窗")
        case .closeWindows:
            return VehicleControlRequestPlan(command: .closeWindows, endpointCandidates: ["car/control/window"], bodyKeys: ["vin", "status"], note: "BLE_SPEC v7.1：车窗 status=1 关车窗")
        case .quickCool:
            return VehicleControlRequestPlan(command: .quickCool, endpointCandidates: ["car/control/acc"], bodyKeys: ["vin", "accOnOff", "status", "temperature", "blowerLvl", "duration"], note: "BLE_SPEC v7.1：快速降温 status=4，temperature=目标温度，blowerLvl=7，duration=5~20")
        }
    }

    /// 根据命令生成请求草稿。
    /// 构造 URL / headers / body 后由 transport 层发送，远程熄火等未确认命令会在此处阻止。
    func makeVehicleControlRequestDraft(accessToken: String, vin: String, command: VehicleCommand) -> Result<VehicleControlRequestDraft, SGMWApiError> {
        let plan = makeVehicleControlRequestPlan(for: command)
        guard let endpoint = plan.endpointCandidates.first else {
            return .failure(.invalidResponse(plan.note))
        }
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else {
            return .failure(.invalidResponse("控制接口 URL 构造失败"))
        }
        var body: [String: Any] = [:]
        if plan.bodyKeys.contains("vin") { body["vin"] = vin }
        if plan.bodyKeys.contains("status") {
            switch command.kind {
            case .lock, .closeWindows:
                body["status"] = 1
            case .unlock, .findCar, .openWindows:
                body["status"] = 0
            case .quickCool:
                body["status"] = 4
            case .acOn:
                body["status"] = 6
            case .acOff:
                body["status"] = 7
            default:
                break
            }
        }
        if plan.bodyKeys.contains("accOnOff") {
            switch command.kind {
            case .acOn, .quickCool:
                body["accOnOff"] = "1"
            case .acOff:
                body["accOnOff"] = "0"
            default:
                break
            }
        }
        if plan.bodyKeys.contains("temperature") {
            let defaultTemperature = command.kind == .quickCool ? 17 : 22
            let rawTemperature = Int(command.requestedTemperature ?? Double(defaultTemperature))
            body["temperature"] = max(17, min(33, rawTemperature))
        }
        if plan.bodyKeys.contains("blowerLvl") { body["blowerLvl"] = 7 }
        if plan.bodyKeys.contains("duration") {
            let rawDuration = command.requestedDurationMinutes ?? 10
            body["duration"] = max(5, min(20, rawDuration))
        }
        if plan.bodyKeys.contains("qgRemoteStopExtendedObjects") {
            body["remoteControlExtendedObjectList"] = [
                [
                    "controlObjective": "19",
                    "rctlVhlParams": [
                        "ctlSwitchStatus": "0",
                        "ctlMode": "40"
                    ]
                ],
                [
                    "controlObjective": "17",
                    "rctlVhlParams": [
                        "ctlSwitchStatus": "0",
                        "goalValue2": "10",
                        "unitOfValue2": "2"
                    ]
                ]
            ]
            body["rctlSendTime"] = currentRemoteControlTimeString()
        }
        let headers = buildSignedHeaders(accessToken: accessToken)
        return .success(VehicleControlRequestDraft(plan: plan, url: url, headers: headers, body: body))
    }

    /// 发送控制请求草稿。
    /// 是否真正代表车辆执行成功以后续 MQTT / 车辆状态回执为准。
    func sendVehicleControlRequestDraft(_ draft: VehicleControlRequestDraft, completion: @escaping (Result<[String: Any], SGMWApiError>) -> Void) {
        var request = URLRequest(url: draft.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.allHTTPHeaderFields = draft.headers
        request.httpBody = try? JSONSerialization.data(withJSONObject: draft.body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(error)))
                return
            }
            guard let data else {
                completion(.failure(.network(nil)))
                return
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let preview = String(data: data, encoding: .utf8).map { String($0.prefix(100)) }
                completion(.failure(.invalidResponse("HTTP \(httpResponse.statusCode)\(preview.map { "：\($0)" } ?? "")")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let preview = String(data: data, encoding: .utf8).map { String($0.prefix(100)) }
                completion(.failure(.parseFailed(preview)))
                return
            }
            if let result = json["result"] as? Bool, result == true {
                completion(.success(json))
                return
            }
            if let code = (json["code"] as? String) ?? (json["statusCode"] as? String),
               ["0", "1", "200", "2000"].contains(code) {
                completion(.success(json))
                return
            }
            if let errorFlag = json["errorFlag"] as? Int, errorFlag == 0 {
                completion(.success(json))
                return
            }
            let msg = (json["msg"] as? String) ?? (json["message"] as? String) ?? "未知错误"
            if msg.contains("token") || msg.contains("Token") || json["code"] as? String == "2002" {
                completion(.failure(.invalidToken))
            } else {
                completion(.failure(.serverMessage(msg)))
            }
        }.resume()
    }

    /// 查询胎压信息（Result 版本）
    func queryTirePressureResult(accessToken: String, vin: String, completion: @escaping (Result<[String: String], SGMWApiError>) -> Void) {
        apiCallResult(
            endpoint: "car/info/tire/pressure",
            body: ["vin": vin],
            accessToken: accessToken
        ) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let json):
                guard let dataObj = json["data"] as? [String: Any] else {
                    completion(.failure(.parseFailed("缺少 tirePressure data")))
                    return
                }
                completion(.success(self.stringifyDictionary(dataObj)))
            }
        }
    }

    /// 查询 BLE 钥匙信息（Result 版本）
    func queryBleKeyResult(accessToken: String, vin: String, phone: String, completion: @escaping (Result<[String: String], SGMWApiError>) -> Void) {
        apiCallResult(
            endpoint: "car/control/ble/key/query",
            body: [
                "vin": vin,
                "userId": phone,
                "mobile": phone
            ],
            accessToken: accessToken
        ) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let json):
                guard let dataObj = json["data"] as? [String: Any] else {
                    completion(.failure(.parseFailed("缺少 data")))
                    return
                }
                completion(.success(self.stringifyDictionary(dataObj)))
            }
        }
    }

    /// 调用 API 获取 mqttToken（Result 版本）
    func fetchMqttTokenResult(accessToken: String, vin: String, completion: @escaping (Result<String, SGMWApiError>) -> Void) {
        apiCallResult(endpoint: "base/mqtt/auth", body: ["vin": vin], accessToken: accessToken) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let json):
                guard let dataObj = json["data"] as? [String: Any],
                      let token = self.stringValue(dataObj["token"]) ?? self.stringValue(dataObj["mqttToken"]),
                      !token.isEmpty else {
                    completion(.failure(.parseFailed("缺少 mqttToken")))
                    return
                }
                completion(.success(token))
            }
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

    private func apiCallResult(endpoint: String, body: [String: Any], accessToken: String, completion: @escaping (Result<[String: Any], SGMWApiError>) -> Void) {
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else {
            completion(.failure(.invalidResponse("URL 构造失败")))
            return
        }

        let headers = buildSignedHeaders(accessToken: accessToken)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.allHTTPHeaderFields = headers
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(error)))
                return
            }
            guard let data else {
                completion(.failure(.network(nil)))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let preview = String(data: data, encoding: .utf8).map { String($0.prefix(100)) }
                completion(.failure(.parseFailed(preview)))
                return
            }
            if let result = json["result"] as? Bool, result == true {
                completion(.success(json))
                return
            }
            // 业务错误
            let msg = (json["msg"] as? String) ?? (json["message"] as? String) ?? "未知错误"
            if msg.contains("token") || msg.contains("Token") || json["code"] as? String == "2002" {
                completion(.failure(.invalidToken))
            } else {
                completion(.failure(.serverMessage(msg)))
            }
        }.resume()
    }

    /// 旧版 apiCall（向下兼容，内部转为 apiCallResult）
    private func apiCall(endpoint: String, body: [String: Any], accessToken: String, completion: @escaping ([String: Any]?) -> Void) {
        apiCallResult(endpoint: endpoint, body: body, accessToken: accessToken) { result in
            switch result {
            case .success(let json): completion(json)
            case .failure: completion(nil)
            }
        }
    }

    private func currentRemoteControlTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
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
