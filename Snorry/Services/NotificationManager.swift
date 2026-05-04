import UserNotifications
import os.log

// MARK: - Wraps UNUserNotificationCenter for snore alerts
final class NotificationManager: @unchecked Sendable {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "app.Snorry", category: "Notifications")

    private let primaryAlertIdentifier = "snorry.snoring.alert"
    private let repeatIdentifierPrefix   = "snorry.snoring.repeat."
    /// Pending repeat deliveries — cleared when alerts cancel.
    private var trackedRepeatIdentifiers: [String] = []

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

    /// First push when entering the notified phase.
    func scheduleSnoringAlert() {
        scheduleDelivery(identifier: primaryAlertIdentifier)
    }

    /// Additional pushes while snoring continues (unique identifier each time).
    func scheduleSnoringAlertRepeat() {
        let identifier = repeatIdentifierPrefix + UUID().uuidString
        trackedRepeatIdentifiers.append(identifier)
        if trackedRepeatIdentifiers.count > 120 {
            trackedRepeatIdentifiers.removeFirst(trackedRepeatIdentifiers.count - 120)
        }
        scheduleDelivery(identifier: identifier)
    }

    private func scheduleDelivery(identifier: String) {
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
                identifier: identifier,
                content: content,
                trigger: nil
            )

            self.center.add(request) { error in
                if let error {
                    self.logger.error("Failed to schedule notification: \(error)")
                }
            }
        }
    }

    func cancelSnoringAlert() {
        let pendingIds = [primaryAlertIdentifier] + trackedRepeatIdentifiers
        center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        center.removeDeliveredNotifications(withIdentifiers: [primaryAlertIdentifier])
        trackedRepeatIdentifiers.removeAll()
    }
}
