import AppKit
import UserNotifications

@MainActor
final class NotificationsController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsController()

    private let categoryID = "STORAGE_ALERT"
    private let openActionID = "OPEN_APP"
    private var ready = false

    func bootstrap() {
        guard Bundle.main.bundleIdentifier != nil, !ready else { return }
        ready = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: openActionID, title: "Open MrMcLean", options: [.foreground])
        let category = UNNotificationCategory(identifier: categoryID, actions: [open],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        guard ready else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { MainWindow.show() }
    }
}
