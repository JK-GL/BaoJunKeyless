import Foundation
import UserNotifications

final class AppNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var isConfigured = false

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        center.delegate = self
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    /// - Parameters:
    ///   - source: keyless / powerOff / background / other；nil 时按标题推断
    func postKeylessNotification(title: String, body: String, source: String? = nil) {
        configure()
        let resolvedSource = source ?? NotificationHistoryStore.inferSource(title: title)

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.record(title: title, body: body, source: resolvedSource, delivered: true)
                self.enqueueNotification(title: title, body: body)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    // 权限拒绝也记录，便于日志页对照“App 想推什么”。
                    self.record(title: title, body: body, source: resolvedSource, delivered: granted)
                    if granted {
                        self.enqueueNotification(title: title, body: body)
                    }
                }
            case .denied:
                self.record(title: title, body: body, source: resolvedSource, delivered: false)
            @unknown default:
                self.record(title: title, body: body, source: resolvedSource, delivered: false)
            }
        }
    }

    private func record(title: String, body: String, source: String, delivered: Bool) {
        Task { @MainActor in
            NotificationHistoryStore.shared.add(
                title: title,
                body: body,
                source: source,
                delivered: delivered
            )
        }
    }

    private func enqueueNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "BaoJunKeyless.keyless.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

// MARK: - 通知名称统一定义
extension Notification.Name {
    static let openAddressFloatingWindow = Notification.Name("OpenAddressFloatingWindow")
}
