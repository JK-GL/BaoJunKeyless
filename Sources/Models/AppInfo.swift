import Foundation
import UIKit

enum AppInfo {
    static var pluginVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return raw.hasPrefix("v") ? raw : "v\(raw)"
    }

    static var buildDate: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "20260606.0000"
    }

    static var systemVersion: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    static var jailbreakEnvironment: String {
        "Dopamine Rootless"
    }
}
