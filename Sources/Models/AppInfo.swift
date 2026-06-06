import Foundation
import UIKit

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var systemVersion: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    static var memoryText: String {
        CrashLogger.formatBytes(ProcessInfo.processInfo.physicalMemory)
    }
}
