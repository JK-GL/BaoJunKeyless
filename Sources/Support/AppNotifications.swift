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

    func postKeylessNotification(title: String, body: String) {
        configure()
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.enqueueNotification(title: title, body: body)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        self.enqueueNotification(title: title, body: body)
                    }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func enqueueNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: "BaoJunKeyless.keyless.\(UUID().uuidString)", content: content, trigger: trigger)
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
