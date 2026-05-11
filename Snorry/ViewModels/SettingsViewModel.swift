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
    /// True while the bulk-delete operation is running.
    private(set) var isDeletingLogs = false

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
        guard !isDeletingLogs else { return }
        stopAlarmStylePreview()
        deleteLogsFailedMessage = nil

        Task { @MainActor in
            isDeletingLogs = true
            defer { isDeletingLogs = false }

            // Prevent a debounced clip-path save (from monitoring) from firing after rows are deleted.
            SessionStore.cancelPendingDebouncedSave(for: context)

            do {
                // Do not wipe rows while monitoring is active; that can leave live pipelines pointing
                // at deleted models and make the app appear frozen until restart.
                let activeDescriptor = FetchDescriptor<SnoreSession>(
                    predicate: #Predicate<SnoreSession> { $0.endDate == nil }
                )
                let hasActiveSession = try !context.fetch(activeDescriptor).isEmpty
                if hasActiveSession {
                    deleteLogsFailedMessage = "Stop monitoring before deleting logs."
                    return
                }

                let sessions = try context.fetch(FetchDescriptor<SnoreSession>())
                var clipURLs: [URL] = []
                clipURLs.reserveCapacity(sessions.count * 2)

                for (index, session) in sessions.enumerated() {
                    clipURLs.append(contentsOf: session.events.compactMap(\.audioURL))
                    context.delete(session)

                    // Batch flushes keep large deletions responsive.
                    if index.isMultiple(of: 40) {
                        try context.save()
                        await Task.yield()
                    }
                }

                let changes = try context.fetch(FetchDescriptor<AlertSettingsChange>())
                for (index, change) in changes.enumerated() {
                    context.delete(change)
                    if index.isMultiple(of: 120) {
                        try context.save()
                        await Task.yield()
                    }
                }

                // Avoid pointing at a deleted session if monitoring state was left in UserDefaults.
                UserDefaults.standard.removeObject(forKey: "currentSessionID")
                try context.save()

                Task.detached(priority: .utility) {
                    Self.deleteClipFiles(urls: clipURLs)
                }
            } catch {
                deleteLogsFailedMessage = error.localizedDescription
            }
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
