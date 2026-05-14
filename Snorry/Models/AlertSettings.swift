import Foundation
import SwiftData

// MARK: - User-configurable alert escalation thresholds
/// One row is always maintained; use AlertSettings.load(context:) to access it.
@Model
final class AlertSettings {

    /// Seconds of continuous snoring before first push notification is sent.
    var notifyDelaySeconds: Double
    /// Seconds of continuous snoring before the sound alarm begins (stepped bursts).
    var soundAlarmAfterSeconds: Double

    /// Master output level (0–1) used for sound alerts and style preview playback. Fixed at full level in app builds.
    var alarmVolume: Float

    /// Snore detection sensitivity (1 = low, 5 = very high). User-facing control removed; value is fixed at maximum.
    var snoringDetectionSensitivity: Double

    /// Raw value of the selected `AlarmStyle` (stored as Int for SwiftData compatibility).
    var alarmStyleRaw: Int

    /// When false, no push notifications are sent (timing sliders for push are ignored).
    var pushNotificationEnabled: Bool
    /// When false, no in-app sound alarm (volume/style ignored for playback).
    var soundAlarmEnabled: Bool
    /// Legacy field kept for compatibility; repeat push is always enabled in current UI/runtime.
    var pushRepeatEnabled: Bool
    /// Seconds between repeated push notifications.
    var pushRepeatIntervalSeconds: Double

    init() {
        notifyDelaySeconds        = 2
        soundAlarmAfterSeconds    = 10
        alarmVolume               = 1.0
        snoringDetectionSensitivity = 5
        alarmStyleRaw             = AlarmStyle.marimbaIntrumental.rawValue
        pushNotificationEnabled   = false
        soundAlarmEnabled         = false
        pushRepeatEnabled         = true
        pushRepeatIntervalSeconds = 3
    }

    /// Returns existing or creates default settings. Normalizes snore sensitivity and alarm volume to current app defaults.
    @MainActor
    static func load(context: ModelContext) -> AlertSettings {
        let descriptor = FetchDescriptor<AlertSettings>()
        if let existing = try? context.fetch(descriptor).first {
            let needsNormalize =
                existing.snoringDetectionSensitivity != 5
                || abs(Double(existing.alarmVolume) - 1.0) > 0.0001
            if needsNormalize {
                existing.snoringDetectionSensitivity = 5
                existing.alarmVolume = 1.0
                try? context.save()
            }
            return existing
        }
        let settings = AlertSettings()
        context.insert(settings)
        return settings
    }
}
