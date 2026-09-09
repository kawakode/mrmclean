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

    func authorizationDescription() async -> String {
        guard ready else { return "Notifications are available when running the app bundle." }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return "Notifications are allowed in macOS."
        case .denied: return "Notifications are blocked. Allow MrMcLean in System Settings → Notifications."
        default: return "Allow notifications in macOS to receive alerts."
        }
    }

    func post(title: String, body: String) async -> Bool {
        guard ready else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = categoryID
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch { return false }
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
