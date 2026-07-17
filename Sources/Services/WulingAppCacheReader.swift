import Foundation

// MARK: - 官方 App 本地缓存读取器
// 只读取本机官方 App（com.cloudy.LingLingBang）的本地数据：
// - AppGroup/SavedOAuthModel（token）
// - Preferences/com.cloudy.LingLingBang.plist（状态缓存/地址缓存）
final class WulingAppCacheReader {
    static let shared = WulingAppCacheReader()

    private let appGroupIdentifier = "group.com.cloudy.LingLingBang"
    private let plistCandidates = [
        "/var/mobile/Library/Preferences/com.cloudy.LingLingBang.plist",
        "/private/var/mobile/Library/Preferences/com.cloudy.LingLingBang.plist"
    ]

    struct TokenInfo {
        let token: String
        let sourcePath: String
    }

    struct CacheSnapshot {
        let sourcePath: String
        let carStatus: [String: String]
        let address: String?
        let cityName: String?
        let latitude: Double?
        let longitude: Double?
    }

    private init() {}

    // MARK: - Token

    func readTokenInfo() -> TokenInfo? {
        for url in savedOAuthModelCandidates() {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let token = (json["access_token"] as? String)
                ?? ((json["data"] as? [String: Any])?["access_token"] as? String)

            if let token, !token.isEmpty {
                return TokenInfo(token: token, sourcePath: url.path)
            }
        }
        return nil
    }

    // MARK: - 官方 App 状态缓存

    func readStatusCache() -> CacheSnapshot? {
        for path in plistCandidates {
            guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }

            let carStatus = extractCarStatus(from: dict)
            let address = stringValue(dict["LastAddress"])
            let cityName = stringValue(dict["kCurrentCityName"])
            let latitude = doubleValue(dict["LastLatitude"])
            let longitude = doubleValue(dict["LastLongitude"])

            if !carStatus.isEmpty || address != nil || latitude != nil || longitude != nil {
                return CacheSnapshot(
                    sourcePath: path,
                    carStatus: carStatus,
                    address: address,
                    cityName: cityName,
                    latitude: latitude,
                    longitude: longitude
                )
            }
        }
        return nil
    }

    // MARK: - 内部工具

    private func savedOAuthModelCandidates() -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default

        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(groupURL.appendingPathComponent("SavedOAuthModel"))
        }

        let manualCopies = [
            "/var/mobile/SavedOAuthModel",
            "/private/var/mobile/SavedOAuthModel"
        ]
        urls.append(contentsOf: manualCopies.map { URL(fileURLWithPath: $0) })

        let appGroupRoots = [
            "/var/mobile/Containers/Shared/AppGroup",
            "/private/var/mobile/Containers/Shared/AppGroup"
        ]

        for root in appGroupRoots {
            guard let items = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                urls.append(URL(fileURLWithPath: root).appendingPathComponent(item).appendingPathComponent("SavedOAuthModel"))
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    private func extractCarStatus(from dict: [String: Any]) -> [String: String] {
        for (key, value) in dict where key.hasPrefix("CYUnifiedCarStatusInfosFor") {
            if let statusDict = value as? [String: Any] {
                if let nested = statusDict["carStatus"] as? [String: Any] {
                    return stringifyDictionary(nested)
                }
                return stringifyDictionary(statusDict)
            }
            if let jsonString = value as? String,
               let data = jsonString.data(using: .utf8),
               let statusDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let nested = statusDict["carStatus"] as? [String: Any] {
                    return stringifyDictionary(nested)
                }
                return stringifyDictionary(statusDict)
            }
        }
        return [:]
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

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let i as Int: return String(i)
        case let d as Double: return String(d)
        default: return nil
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        case let i as Int: return Double(i)
        default: return nil
        }
    }
}
