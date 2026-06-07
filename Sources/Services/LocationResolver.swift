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

    // MARK: - 逆地理编码
    func getAddress(wgs84Lat: Double, wgs84Lng: Double, completion: @escaping (String?) -> Void) {
        let gcj = Self.wgs84ToGcj02(lat: wgs84Lat, lng: wgs84Lng)
        let location = CLLocation(latitude: gcj.lat, longitude: gcj.lng)

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let p = placemarks?.first else {
                completion(self?.cachedAddress)
                return
            }

            let address = self?.buildAddress(from: p) ?? ""

            UserDefaults.standard.set(address, forKey: "LastAddress")
            UserDefaults.standard.set(gcj.lat, forKey: "LastLatitude")
            UserDefaults.standard.set(gcj.lng, forKey: "LastLongitude")

            completion(address.isEmpty ? nil : address)
        }
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
