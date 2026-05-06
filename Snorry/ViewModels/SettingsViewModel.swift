import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {

    private static let timingRange: ClosedRange<Double> = 1...10

    var notifyDelay: Double     = 2
    var soundAlarmAfter: Double = 10
    var alarmVolume: Float      = 0.85

    var pushNotificationEnabled: Bool = true
    var soundAlarmEnabled: Bool       = true
    var pushRepeatEnabled: Bool       = false
    var pushRepeatInterval: Double    = 10

    /// Snore detection sensitivity level (1–5). 3 = factory default.
    var snoringDetectionSensitivity: Double = 3

    /// Selected alarm tone style.
    var alarmStyle: AlarmStyle = .classic

    private let context: ModelContext
    private var settings: AlertSettings?

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
        alarmVolume                   = stored.alarmVolume
        pushNotificationEnabled       = stored.pushNotificationEnabled
        soundAlarmEnabled             = stored.soundAlarmEnabled
        pushRepeatEnabled             = stored.pushRepeatEnabled
        pushRepeatInterval            = Self.clampTiming(stored.pushRepeatIntervalSeconds)
        snoringDetectionSensitivity   = stored.snoringDetectionSensitivity
        alarmStyle                    = AlarmStyle(rawValue: stored.alarmStyleRaw) ?? .classic
    }

    func save() {
        guard let stored = settings else { return }

        // Enforce supported timing slider range even for legacy persisted values.
        notifyDelay = Self.clampTiming(notifyDelay)
        soundAlarmAfter = Self.clampTiming(soundAlarmAfter)
        pushRepeatInterval = Self.clampTiming(pushRepeatInterval)

        // Record a change snapshot before writing if any tracked push/alarm field changed.
        let hasChanged = stored.pushNotificationEnabled    != pushNotificationEnabled
            || stored.soundAlarmEnabled                    != soundAlarmEnabled
            || stored.pushRepeatEnabled                    != pushRepeatEnabled
            || stored.notifyDelaySeconds                   != notifyDelay
            || stored.soundAlarmAfterSeconds               != soundAlarmAfter
            || stored.pushRepeatIntervalSeconds            != pushRepeatInterval
            || stored.alarmStyleRaw                        != alarmStyle.rawValue

        stored.notifyDelaySeconds              = notifyDelay
        stored.soundAlarmAfterSeconds          = soundAlarmAfter
        stored.alarmVolume                     = alarmVolume
        stored.pushNotificationEnabled         = pushNotificationEnabled
        stored.soundAlarmEnabled               = soundAlarmEnabled
        stored.pushRepeatEnabled               = pushRepeatEnabled
        stored.pushRepeatIntervalSeconds       = pushRepeatInterval
        stored.snoringDetectionSensitivity     = snoringDetectionSensitivity
        stored.alarmStyleRaw                   = alarmStyle.rawValue

        if hasChanged {
            let change = AlertSettingsChange(
                pushNotificationEnabled: pushNotificationEnabled,
                notifyDelaySeconds: notifyDelay,
                pushRepeatEnabled: pushRepeatEnabled,
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
        load()
    }

    func reset() {
        if let old = settings { context.delete(old) }
        let fresh = AlertSettings()
        context.insert(fresh)
        settings = fresh
        load()
    }

    private static func clampTiming(_ value: Double) -> Double {
        min(max(value, timingRange.lowerBound), timingRange.upperBound)
    }
}
