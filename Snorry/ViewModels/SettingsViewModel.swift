import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {

    private static let timingRange: ClosedRange<Double> = 1...10

    var notifyDelay: Double     = 2
    var soundAlarmAfter: Double = 10
    var alarmVolume: Float      = 0.50

    var pushNotificationEnabled: Bool = true
    var soundAlarmEnabled: Bool       = true
    var pushRepeatEnabled: Bool       = true
    var pushRepeatInterval: Double    = 3

    /// Snore detection sensitivity level (1–5). 3 = factory default.
    var snoringDetectionSensitivity: Double = 3

    /// Selected alarm tone style.
    var alarmStyle: AlarmStyle = .marimbaIntrumental
    /// Alarm style currently being previewed in Settings.
    private(set) var previewingAlarmStyle: AlarmStyle?

    /// Set when bulk log deletion fails so the UI can show an alert.
    private(set) var deleteLogsFailedMessage: String?

    private let context: ModelContext
    private var settings: AlertSettings?
    private let alarmPreviewPlayer = AlarmTonePlayer()

    init(context: ModelContext) {
        self.context = context
        load()
    }

    // MARK: Persistence

    private func load() {
        let stored = AlertSettings.load(context: context)
        settings = stored
        notifyDelay                   = Self.clampTiming(stored.notifyDelaySeconds)
        soundAlarmAfter               = Self.clampTiming(stored.soundAlarmAfterSeconds)
        alarmVolume                   = Self.clampAlarmVolume(stored.alarmVolume)
        pushNotificationEnabled       = stored.pushNotificationEnabled
        soundAlarmEnabled             = stored.soundAlarmEnabled
        // Repeat push notifications are now always enabled; only interval is user-configurable.
        pushRepeatEnabled             = true
        pushRepeatInterval            = Self.clampTiming(stored.pushRepeatIntervalSeconds)
        snoringDetectionSensitivity   = stored.snoringDetectionSensitivity
        alarmStyle                    = AlarmStyle(rawValue: stored.alarmStyleRaw) ?? .classic
    }

    func save() {
        stopAlarmStylePreview()
        guard let stored = settings else { return }

        // Enforce supported timing slider range even for legacy persisted values.
        notifyDelay = Self.clampTiming(notifyDelay)
        soundAlarmAfter = Self.clampTiming(soundAlarmAfter)
        pushRepeatInterval = Self.clampTiming(pushRepeatInterval)
        alarmVolume = Self.clampAlarmVolume(alarmVolume)

        // Record a change snapshot before writing if any tracked push/alarm field changed.
        let hasChanged = stored.pushNotificationEnabled    != pushNotificationEnabled
            || stored.soundAlarmEnabled                    != soundAlarmEnabled
            || stored.pushRepeatEnabled                    != true
            || stored.notifyDelaySeconds                   != notifyDelay
            || stored.soundAlarmAfterSeconds               != soundAlarmAfter
            || stored.alarmVolume                          != alarmVolume
            || stored.pushRepeatIntervalSeconds            != pushRepeatInterval
            || stored.alarmStyleRaw                        != alarmStyle.rawValue

        stored.notifyDelaySeconds              = notifyDelay
        stored.soundAlarmAfterSeconds          = soundAlarmAfter
        stored.alarmVolume                     = alarmVolume
        stored.pushNotificationEnabled         = pushNotificationEnabled
        stored.soundAlarmEnabled               = soundAlarmEnabled
        stored.pushRepeatEnabled               = true
        stored.pushRepeatIntervalSeconds       = pushRepeatInterval
        stored.snoringDetectionSensitivity     = snoringDetectionSensitivity
        stored.alarmStyleRaw                   = alarmStyle.rawValue

        if hasChanged {
            let change = AlertSettingsChange(
                pushNotificationEnabled: pushNotificationEnabled,
                notifyDelaySeconds: notifyDelay,
                pushRepeatEnabled: true,
                pushRepeatIntervalSeconds: pushRepeatInterval,
                soundAlarmEnabled: soundAlarmEnabled,
                soundAlarmAfterSeconds: soundAlarmAfter,
                alarmStyleRaw: alarmStyle.rawValue
            )
            context.insert(change)
        }

        try? context.save()
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
        stopAlarmStylePreview()
        deleteLogsFailedMessage = nil
        // Prevent a debounced clip-path save (from monitoring) from firing after rows are deleted.
        SessionStore.cancelPendingDebouncedSave(for: context)
        do {
            let sessions = try context.fetch(FetchDescriptor<SnoreSession>())
            for session in sessions {
                for event in session.events {
                    if let url = event.audioURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                context.delete(session)
            }
            let changes = try context.fetch(FetchDescriptor<AlertSettingsChange>())
            for change in changes {
                context.delete(change)
            }
            // Avoid pointing at a deleted session if monitoring state was left in UserDefaults.
            UserDefaults.standard.removeObject(forKey: "currentSessionID")
            try context.save()
        } catch {
            deleteLogsFailedMessage = error.localizedDescription
        }
    }

    func clearDeleteLogsError() {
        deleteLogsFailedMessage = nil
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
        alarmPreviewPlayer.play(volume: alarmVolume)
    }

    private static func clampTiming(_ value: Double) -> Double {
        min(max(value, timingRange.lowerBound), timingRange.upperBound)
    }

    private static func clampAlarmVolume(_ value: Float) -> Float {
        min(max(value, 0.10), 1.0)
    }
}
