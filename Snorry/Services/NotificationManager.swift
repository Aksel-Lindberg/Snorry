import UserNotifications
import os.log

// MARK: - Wraps UNUserNotificationCenter for snore alerts
final class NotificationManager: @unchecked Sendable {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "app.Snorry", category: "Notifications")

    private(set) var isAuthorized = false

    private init() {}

    // MARK: Authorisation

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            logger.info("Notification authorisation granted: \(granted)")
        } catch {
            logger.error("Notification auth error: \(error)")
        }
    }

    func checkAuthorisationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Alert scheduling

    /// Deliver an immediate local notification indicating snoring is detected.
    /// Re-checks authorization at delivery time (user may have changed Settings).
    func scheduleSnoringAlert() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            guard settings.authorizationStatus == .authorized else {
                self.logger.warning("Skipping snoring alert — notifications not authorized")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Snoring Detected"
            content.body  = "Snorry has detected a snoring pattern. Tap to view details."
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let request = UNNotificationRequest(
                identifier: "snorry.snoring.alert",
                content: content,
                trigger: nil   // deliver immediately
            )

            self.center.add(request) { error in
                if let error {
                    self.logger.error("Failed to schedule notification: \(error)")
                }
            }
        }
    }

    func cancelSnoringAlert() {
        center.removePendingNotificationRequests(withIdentifiers: ["snorry.snoring.alert"])
        center.removeDeliveredNotifications(withIdentifiers: ["snorry.snoring.alert"])
    }
}
