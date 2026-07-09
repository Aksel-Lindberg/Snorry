import Foundation
import SwiftData
import UserNotifications

@Observable
@MainActor
final class SettingsViewModel {

    var pushNotificationEnabled: Bool = true
    var soundAlarmEnabled: Bool       = true

    /// Selected alarm tone style.
    var alarmStyle: AlarmStyle = .bell
    /// Alarm style currently being previewed in Settings.
    private(set) var previewingAlarmStyle: AlarmStyle?

    /// Shown when the user enables push but iOS notifications are denied (Settings app).
    private(set) var pushNotificationsBlockedMessage: String?

    /// Set when bulk log deletion fails so the UI can show an alert.
    private(set) var deleteLogsFailedMessage: String?
    /// True while the bulk-delete operation is running.
    private(set) var isDeletingLogs = false

    private let context: ModelContext
    /// Used for bulk deletion off the main actor so the UI stays responsive with large histories.
    private let modelContainer: ModelContainer
    private var settings: AlertSettings?
    private let alarmPreviewPlayer = AlarmTonePlayer()

    init(context: ModelContext) {
        self.context = context
        self.modelContainer = context.container
        load()
    }

    // MARK: Persistence

    private func load() {
        let stored = AlertSettings.load(context: context)
        settings = stored
        pushNotificationEnabled       = stored.pushNotificationEnabled
        soundAlarmEnabled             = stored.soundAlarmEnabled
        alarmStyle                    = AlarmStyle(rawValue: stored.alarmStyleRaw) ?? .classic
    }

    func save() {
        stopAlarmStylePreview()
        guard let stored = settings else { return }

        // Record a change snapshot before writing if any tracked push/alarm field changed.
        let changeFlags = SettingsChangeFlags(
            pushEnabled: stored.pushNotificationEnabled != pushNotificationEnabled,
            soundAlarmEnabled: stored.soundAlarmEnabled != soundAlarmEnabled,
            alarmTone: stored.alarmStyleRaw != alarmStyle.rawValue
        )
        let hasChanged = changeFlags.pushEnabled
            || changeFlags.soundAlarmEnabled
            || changeFlags.alarmTone

        stored.notifyDelaySeconds              = AlertTimingDefaults.notifyDelaySeconds
        stored.soundAlarmAfterSeconds          = AlertTimingDefaults.soundAlarmAfterSeconds
        stored.alarmVolume                     = 1.0
        stored.pushNotificationEnabled         = pushNotificationEnabled
        stored.soundAlarmEnabled               = soundAlarmEnabled
        stored.pushRepeatEnabled               = true
        stored.snoringDetectionSensitivity     = 5
        stored.alarmStyleRaw                   = alarmStyle.rawValue

        if hasChanged {
            let change = AlertSettingsChange(
                pushNotificationEnabled: pushNotificationEnabled,
                notifyDelaySeconds: AlertTimingDefaults.notifyDelaySeconds,
                pushRepeatEnabled: true,
                pushRepeatIntervalSeconds: 0,
                soundAlarmEnabled: soundAlarmEnabled,
                soundAlarmAfterSeconds: AlertTimingDefaults.soundAlarmAfterSeconds,
                alarmStyleRaw: alarmStyle.rawValue
            )
            context.insert(change)
        }

        try? context.save()
        if hasChanged {
            AppAnalytics.logSettingsSaved(changes: changeFlags)
        }
        NotificationCenter.default.post(name: .snorryAlertSettingsDidSave, object: nil)
    }

    func cancel() {
        stopAlarmStylePreview()
        load()
    }

    func reset() {
        stopAlarmStylePreview()
        if let old = settings { context.delete(old) }
        let fresh = AlertSettings()
        context.insert(fresh)
        settings = fresh
        load()
    }

    /// Removes all sleep sessions (events, waveforms, snore clips on disk) and `AlertSettingsChange` analytics markers.
    /// Does not alter current `AlertSettings` preferences.
    func deleteAllSleepAndSettingsLogs() {
        guard !isDeletingLogs else { return }
        stopAlarmStylePreview()
        deleteLogsFailedMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Prevent a debounced clip-path save (from monitoring) from firing after rows are deleted.
            SessionStore.cancelPendingDebouncedSave(for: self.context)

            do {
                // Do not wipe rows while monitoring is active; that can leave live pipelines pointing
                // at deleted models and make the app appear frozen until restart.
                let activeDescriptor = FetchDescriptor<SnoreSession>(
                    predicate: #Predicate<SnoreSession> { $0.endDate == nil }
                )
                let hasActiveSession = try !self.context.fetch(activeDescriptor).isEmpty
                if hasActiveSession {
                    self.deleteLogsFailedMessage = "Stop recording before deleting logs."
                    return
                }
            } catch {
                self.deleteLogsFailedMessage = error.localizedDescription
                return
            }

            self.isDeletingLogs = true
            defer { self.isDeletingLogs = false }

            do {
                let deleter = SleepLogsDeletionActor(modelContainer: self.modelContainer)
                let clipURLs = try await deleter.deleteAllSessionsAndSettingsMarkers()
                UserDefaults.standard.removeObject(forKey: "currentSessionID")
                Task.detached(priority: .utility) {
                    Self.deleteClipFiles(urls: clipURLs)
                }
            } catch {
                self.deleteLogsFailedMessage = error.localizedDescription
            }
        }
    }

    func clearDeleteLogsError() {
        deleteLogsFailedMessage = nil
    }

    func clearPushNotificationsBlockedMessage() {
        pushNotificationsBlockedMessage = nil
    }

    /// Turning push off applies immediately. Turning on runs the system permission flow first.
    func setPushNotificationEnabled(_ enabled: Bool) async {
        if !enabled {
            pushNotificationEnabled = false
            pushNotificationsBlockedMessage = nil
            return
        }

        let allowed = await NotificationManager.shared.ensureAlertDeliveryAuthorized()
        if allowed {
            pushNotificationEnabled = true
            pushNotificationsBlockedMessage = nil
            return
        }

        pushNotificationEnabled = false
        let status = await NotificationManager.shared.checkAuthorisationStatus()
        if status == .denied {
            pushNotificationsBlockedMessage =
                "Notifications are turned off for Snorry. Enable them in Settings to use push alerts."
        }
    }

    // MARK: Alarm style preview

    func isPreviewing(style: AlarmStyle) -> Bool {
        previewingAlarmStyle == style
    }

    func toggleAlarmStylePreview(for style: AlarmStyle) {
        if isPreviewing(style: style) {
            stopAlarmStylePreview()
        } else {
            startAlarmStylePreview(for: style)
        }
    }

    func stopAlarmStylePreview() {
        previewingAlarmStyle = nil
        alarmPreviewPlayer.stop()
        AudioSessionManager.shared.resetReplayOverrides()
    }

    private func startAlarmStylePreview(for style: AlarmStyle) {
        stopAlarmStylePreview()
        do {
            try AudioSessionManager.shared.configureForClipReplay()
        } catch {
            return
        }
        previewingAlarmStyle = style
        alarmPreviewPlayer.setStyle(style)
        alarmPreviewPlayer.play(volume: 1.0)
    }

    /// Best-effort background cleanup for persisted clip files after DB rows are removed.
    nonisolated private static func deleteClipFiles(urls: [URL]) {
        let fileManager = FileManager.default
        var parentDirectories = Set<URL>()

        for url in urls {
            parentDirectories.insert(url.deletingLastPathComponent())
            try? fileManager.removeItem(at: url)
        }

        // Remove any now-empty per-session clip folders.
        for directory in parentDirectories {
            let remaining = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            if remaining.isEmpty {
                try? fileManager.removeItem(at: directory)
            }
        }
    }
}
