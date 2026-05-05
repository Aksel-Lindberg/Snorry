import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {

    var notifyDelay: Double     = 2
    var soundAlarmAfter: Double = 15
    var clearDelay: Double      = 8
    var alarmVolume: Float      = 0.85

    var pushNotificationEnabled: Bool = true
    var soundAlarmEnabled: Bool       = true
    var pushRepeatEnabled: Bool       = false
    var pushRepeatInterval: Double    = 60

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
        notifyDelay                   = stored.notifyDelaySeconds
        soundAlarmAfter               = stored.soundAlarmAfterSeconds
        clearDelay                    = stored.clearDelaySeconds
        alarmVolume                   = stored.alarmVolume
        pushNotificationEnabled       = stored.pushNotificationEnabled
        soundAlarmEnabled             = stored.soundAlarmEnabled
        pushRepeatEnabled             = stored.pushRepeatEnabled
        pushRepeatInterval            = stored.pushRepeatIntervalSeconds
        snoringDetectionSensitivity   = stored.snoringDetectionSensitivity
        alarmStyle                    = AlarmStyle(rawValue: stored.alarmStyleRaw) ?? .classic
    }

    func save() {
        guard let stored = settings else { return }

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
        stored.clearDelaySeconds               = clearDelay
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
}
