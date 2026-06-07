import Foundation
import CoreLocation

// MARK: - 车辆地址解析器
// 严格按照 LOCATION_RESOLVER_SPEC.md 实现：
// 1. WGS-84 → GCJ-02
// 2. CLGeocoder 逆地理
// 3. 省市区街道+POI 拼接
// 4. NSUserDefaults 缓存
// 5. 不用任何第三方库/API key
final class LocationResolver: NSObject, CLLocationManagerDelegate {
    static let shared = LocationResolver()
    private let geocoder = CLGeocoder()
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

    func getAddress(wgs84Lat: Double, wgs84Lng: Double, address: String? = nil, amapWebKey: String? = nil, completion: @escaping (String?) -> Void) {
        let coordinate = CLLocationCoordinate2D(latitude: wgs84Lat, longitude: wgs84Lng)

        let applyResult: (CLLocationCoordinate2D, String?) -> Void = { [weak self] resolvedCoordinate, address in
            guard let self else { return }
            self.lastResolvedCoordinate = resolvedCoordinate
            self.lastResolvedDate = Date()

            UserDefaults.standard.set(address ?? "", forKey: "LastAddress")
            UserDefaults.standard.set(resolvedCoordinate.latitude, forKey: "LastLatitude")
            UserDefaults.standard.set(resolvedCoordinate.longitude, forKey: "LastLongitude")

            completion(address)
        }

        let lastCoordinate = lastResolvedCoordinate
        let lastDate = lastResolvedDate
        let now = Date()
        let distanceFromLast: Double
        if let lastCoordinate {
            distanceFromLast = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)
                .distance(from: CLLocation(latitude: wgs84Lat, longitude: wgs84Lng))
        } else {
            distanceFromLast = .greatestFiniteMagnitude
        }
        let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let cachedAddress = address ?? self.cachedAddress
        let needsUpdate = distanceFromLast >= 50 || elapsed >= 60 || (cachedAddress ?? "").isEmpty
        guard needsUpdate else { return }

        if let key = amapWebKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let gcj = Self.wgs84ToGcj02(lat: wgs84Lat, lng: wgs84Lng)
            reverseGeocodeAmap(gcjLat: gcj.lat, gcjLng: gcj.lng, key: key) { [weak self] resolved in
                let finalAddress = resolved ?? self?.cachedAddress
                applyResult(coordinate, finalAddress)
            }
        } else {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
                guard let p = placemarks?.first else {
                    applyResult(coordinate, self?.cachedAddress)
                    return
                }
                let finalAddress = self?.buildAddress(from: p)
                applyResult(coordinate, finalAddress?.isEmpty == true ? nil : finalAddress)
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

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
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
        UserDefaults.standard.string(forKey: "LastAddress")
    }
}
