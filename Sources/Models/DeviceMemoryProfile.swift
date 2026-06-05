import Foundation
import UIKit

enum DeviceMemoryProfile {
    static let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory

    /// iPhone 13 mini 属于 4GB 档；这类设备对 SwiftUI 大图背景/预览更容易触发 jetsam。
    static var isLowMemoryDevice: Bool {
        physicalMemoryBytes <= 4_500_000_000
    }

    static var shouldUseLightweightImages: Bool {
        isLowMemoryDevice
    }

    static func purgeImageCaches() {
        URLCache.shared.removeAllCachedResponses()
        AppThemeStorage.invalidateBackgroundImageCache()
    }
}
