import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {

    private static let timingRange: ClosedRange<Double> = 1...10
    private static let fixedAlarmStartVolume: Float = 0.10

    var notifyDelay: Double     = 2
    var soundAlarmAfter: Double = 10

    var pushNotificationEnabled: Bool = true
    var soundAlarmEnabled: Bool       = true
    var pushRepeatEnabled: Bool       = true
    var pushRepeatInterval: Double    = 10

    /// Snore detection sensitivity level (1–5). 3 = factory default.
    var snoringDetectionSensitivity: Double = 3

    /// Selected alarm tone style.
    var alarmStyle: AlarmStyle = .classic
    /// Alarm style currently being previewed in Settings.
    private(set) var previewingAlarmStyle: AlarmStyle?

    private let context: ModelContext
    private var settings: AlertSettings?
    private let alarmPreviewPlayer = AlarmTonePlayer()
    private var alarmPreviewTask: Task<Void, Never>?

    /// Seconds between preview volume increases.
    private static let previewStepInterval: TimeInterval = 2

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
        stored.alarmVolume            = Self.fixedAlarmStartVolume
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

        // Record a change snapshot before writing if any tracked push/alarm field changed.
        let hasChanged = stored.pushNotificationEnabled    != pushNotificationEnabled
            || stored.soundAlarmEnabled                    != soundAlarmEnabled
            || stored.pushRepeatEnabled                    != true
            || stored.notifyDelaySeconds                   != notifyDelay
            || stored.soundAlarmAfterSeconds               != soundAlarmAfter
            || stored.pushRepeatIntervalSeconds            != pushRepeatInterval
            || stored.alarmStyleRaw                        != alarmStyle.rawValue

        stored.notifyDelaySeconds              = notifyDelay
        stored.soundAlarmAfterSeconds          = soundAlarmAfter
        stored.alarmVolume                     = Self.fixedAlarmStartVolume
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
        alarmPreviewTask?.cancel()
        alarmPreviewTask = nil
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
        alarmPreviewTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentVolume = Self.fixedAlarmStartVolume
            while !Task.isCancelled {
                self.alarmPreviewPlayer.play(volume: currentVolume)
                currentVolume = min(1.0, currentVolume + 0.1)
                try? await Task.sleep(for: .seconds(Self.previewStepInterval))
            }
        }
    }

    private static func clampTiming(_ value: Double) -> Double {
        min(max(value, timingRange.lowerBound), timingRange.upperBound)
    }
}
