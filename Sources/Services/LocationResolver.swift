import Foundation
import CoreLocation

// MARK: - 车辆地址解析器
// 中国大陆插件显示层统一使用 GCJ-02：
// 1. 首屏优先返回缓存地址
// 2. 实时坐标进入显示层后按 GCJ-02 处理
// 3. 有高德 key 时直接走高德 GCJ-02 路线
// 4. 无 key 时也按 GCJ-02 体系进行兼容解析和缓存
final class LocationResolver: NSObject, CLLocationManagerDelegate {
    static let shared = LocationResolver()
    private let geocoder = CLGeocoder()
    private let displayCacheStore = VehicleDisplayCacheStore()
    private var lastResolvedCoordinate: CLLocationCoordinate2D?
    private var lastResolvedDate: Date?

    private override init() {
        super.init()
    }

    // MARK: - WGS-84 → GCJ-02
    private static let a: Double = 6378245.0
    private static let ee: Double = 0.00669342162296594323

    static func wgs84ToGcj02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        let dLat = transformLat(x: lng - 105, y: lat - 35)
        let dLng = transformLng(x: lng - 105, y: lat - 35)

        let radLat = lat / 180 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        let latOffset = (dLat * 180) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        let lngOffset = (dLng * 180) / (a / sqrtMagic * cos(radLat) * Double.pi)

        return (lat + latOffset, lng + lngOffset)
    }

    /// GCJ-02 → WGS-84（电子围栏 / CoreLocation 用）。迭代反算，精度约米级。
    static func gcj02ToWgs84(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        var wgsLat = lat
        var wgsLng = lng
        for _ in 0..<6 {
            let gcj = wgs84ToGcj02(lat: wgsLat, lng: wgsLng)
            wgsLat -= (gcj.lat - lat)
            wgsLng -= (gcj.lng - lng)
        }
        return (wgsLat, wgsLng)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        ret += (20*sin(6*x*Double.pi) + 20*sin(2*x*Double.pi)) * 2/3
        ret += (20*sin(y*Double.pi) + 40*sin(y/3*Double.pi)) * 2/3
        ret += (160*sin(y/12*Double.pi) + 320*sin(y*Double.pi/30)) * 2/3
        return ret
    }

    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        ret += (20*sin(6*x*Double.pi) + 20*sin(2*x*Double.pi)) * 2/3
        ret += (20*sin(x*Double.pi) + 40*sin(x/3*Double.pi)) * 2/3
        ret += (150*sin(x/12*Double.pi) + 300*sin(x*Double.pi/30)) * 2/3
        return ret
    }

    // MARK: - 设置车辆坐标（GCJ-02）
    func setCarLocation(gcjLat: Double, gcjLng: Double) {
        lastResolvedCoordinate = CLLocationCoordinate2D(latitude: gcjLat, longitude: gcjLng)
        lastResolvedDate = Date()
        displayCacheStore.setCoordinate(latitudeGcj: gcjLat, longitudeGcj: gcjLng)
    }

    func getAddress(gcjLat: Double, gcjLng: Double, address: String? = nil, amapWebKey: String? = nil, completion: @escaping (String?) -> Void) {
        let coordinate = CLLocationCoordinate2D(latitude: gcjLat, longitude: gcjLng)
        let cachedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? address : self.cachedAddress

        if let cachedAddress, !cachedAddress.isEmpty {
            completion(cachedAddress)
        }

        let applyResult: (CLLocationCoordinate2D, String?) -> Void = { [weak self] resolvedCoordinate, resolvedAddress in
            guard let self else { return }
            self.lastResolvedCoordinate = resolvedCoordinate
            self.lastResolvedDate = Date()
            self.displayCacheStore.setAddress(resolvedAddress ?? "")
            self.displayCacheStore.setCoordinate(latitudeGcj: resolvedCoordinate.latitude, longitudeGcj: resolvedCoordinate.longitude)
            completion(resolvedAddress)
        }

        let lastCoordinate = lastResolvedCoordinate
        let lastDate = lastResolvedDate
        let now = Date()
        let distanceFromLast: Double
        if let lastCoordinate {
            distanceFromLast = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
                .distance(from: CLLocation(latitude: gcjLat, longitude: gcjLng))
        } else {
            distanceFromLast = .greatestFiniteMagnitude
        }
        let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let needsUpdate = distanceFromLast >= 50 || elapsed >= 60 || (cachedAddress ?? "").isEmpty
        guard needsUpdate else { return }

        if let key = amapWebKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reverseGeocodeAmap(gcjLat: gcjLat, gcjLng: gcjLng, key: key) { resolved in
                if let resolved, !resolved.isEmpty {
                    applyResult(coordinate, resolved)
                } else {
                    applyResult(coordinate, cachedAddress)
                }
            }
            return
        }

        // 无 key 时优先保留缓存结果，同时异步尝试系统地址解析作为兼容补充。
        // 这里为了统一中国大陆显示层，传入的仍是 GCJ-02 展示坐标。
        let location = CLLocation(latitude: gcjLat, longitude: gcjLng)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            if let p = placemarks?.first {
                let finalAddress = self.buildAddress(from: p)
                applyResult(coordinate, finalAddress.isEmpty ? cachedAddress : finalAddress)
            } else {
                applyResult(coordinate, cachedAddress)
            }
        }
    }

    private func reverseGeocodeAmap(gcjLat: Double, gcjLng: Double, key: String, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://restapi.amap.com/v3/geocode/regeo")
        components?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "location", value: "\(gcjLng),\(gcjLat)"),
            URLQueryItem(name: "extensions", value: "base")
        ]

        guard let url = components?.url else {
            completion(cachedAddress)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, error == nil else {
                completion(self?.cachedAddress)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let regeocode = json["regeocode"] as? [String: Any],
                  let formattedAddress = regeocode["formatted_address"] as? String else {
                completion(self?.cachedAddress)
                return
            }

            DispatchQueue.main.async {
                completion(formattedAddress.isEmpty ? self?.cachedAddress : formattedAddress)
            }
        }.resume()
    }

    // MARK: - 地址拼接
    private func buildAddress(from p: CLPlacemark) -> String {
        var parts: [String] = []

        if let s = p.administrativeArea {
            parts.append(s)
        }

        if let s = p.locality, s != p.administrativeArea {
            parts.append(s)
        }

        if let s = p.subLocality {
            parts.append(s)
        }

        if let s = p.thoroughfare {
            parts.append(s)
        }

        if let s = p.name, !parts.joined().contains(s) {
            parts.append(s)
        }

        return parts.joined()
    }

    // MARK: - 缓存
    var cachedAddress: String? {
        let address = displayCacheStore.loadSnapshot().address
        return address.isEmpty ? nil : address
    }
}
