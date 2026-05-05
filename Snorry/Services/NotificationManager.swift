import UserNotifications
import os.log

// MARK: - Wraps UNUserNotificationCenter for snore alerts
/// Subclasses `NSObject` so it can be `UNUserNotificationCenter.delegate` (`NSObjectProtocol`).
final class NotificationManager: NSObject, @unchecked Sendable {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "app.Snorry", category: "Notifications")

    private let primaryAlertIdentifier = "snorry.snoring.alert"
    private let repeatIdentifierPrefix   = "snorry.snoring.repeat."
    private let defaultPushSoundName = "default"
    /// Pending repeat deliveries — cleared when alerts cancel.
    private var trackedRepeatIdentifiers: [String] = []

    private(set) var isAuthorized = false

    private override init() {
        super.init()
    }

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

            let content = self.makeSnoringAlertContent()

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

    /// Builds a local-notification payload that mirrors APNs fields, including `aps.sound`.
    private func makeSnoringAlertContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Snoring Detected"
        content.body = "Snorry has detected a snoring pattern. Tap to view details."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "aps": [
                "sound": defaultPushSoundName,
                "interruption-level": "time-sensitive"
            ]
        ]
        return content
    }

    func cancelSnoringAlert() {
        let pendingIds = [primaryAlertIdentifier] + trackedRepeatIdentifiers
        center.removePendingNotificationRequests(withIdentifiers: pendingIds)
        center.removeDeliveredNotifications(withIdentifiers: [primaryAlertIdentifier])
        trackedRepeatIdentifiers.removeAll()
    }
}

// MARK: - Foreground presentation

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Without this, iOS suppresses banners while the app is open (e.g. during monitoring).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
