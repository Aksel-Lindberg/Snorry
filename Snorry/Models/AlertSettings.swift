import Foundation
import SwiftData

// MARK: - Fixed alert escalation timings (not user-configurable)

enum AlertTimingDefaults {
    /// Seconds of continuous snoring before the first push notification.
    static let notifyDelaySeconds: TimeInterval = 2
    /// Seconds of continuous snoring before the sound alarm begins.
    static let soundAlarmAfterSeconds: TimeInterval = 5
    /// Seconds without snoring before alerts clear.
    static let clearDelaySeconds: TimeInterval = 3
    /// Pause between sound-alarm bursts while snoring continues.
    static let soundAlarmPauseSeconds: TimeInterval = 3
}

enum SoundAlertVolumeDefaults {
    /// Starts at 12.5%, then +25% per escalation step until full level.
    static let tierFractions: [Float] = [0.125, 0.375, 0.625, 0.875, 1.00]
    /// One burst per tier for built-in tone styles.
    static let burstsPerTier = 1
    /// Seconds per tier for continuous recorded-clip playback.
    static let secondsPerTier: TimeInterval = 3
    static let minimumOutputVolume: Float = 0.10
}

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
        soundAlarmAfterSeconds    = 5
        alarmVolume               = 1.0
        snoringDetectionSensitivity = 5
        alarmStyleRaw             = AlarmStyle.bell.rawValue
        pushNotificationEnabled   = true
        soundAlarmEnabled         = true
        pushRepeatEnabled         = true
        pushRepeatIntervalSeconds = 3
    }

    /// Returns existing or creates default settings. Normalizes legacy rows to current fixed defaults.
    @MainActor
    static func load(context: ModelContext) -> AlertSettings {
        let descriptor = FetchDescriptor<AlertSettings>()
        if let existing = try? context.fetch(descriptor).first {
            let needsNormalize =
                existing.snoringDetectionSensitivity != 5
                || abs(Double(existing.alarmVolume) - 1.0) > 0.0001
                || existing.notifyDelaySeconds != AlertTimingDefaults.notifyDelaySeconds
                || existing.soundAlarmAfterSeconds != AlertTimingDefaults.soundAlarmAfterSeconds
                || !existing.pushRepeatEnabled
            if needsNormalize {
                existing.snoringDetectionSensitivity = 5
                existing.alarmVolume = 1.0
                existing.notifyDelaySeconds = AlertTimingDefaults.notifyDelaySeconds
                existing.soundAlarmAfterSeconds = AlertTimingDefaults.soundAlarmAfterSeconds
                existing.pushRepeatEnabled = true
                try? context.save()
            }
            return existing
        }
        let settings = AlertSettings()
        context.insert(settings)
        return settings
    }
}
