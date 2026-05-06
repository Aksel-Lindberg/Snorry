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

    /// Master output level (0–1) used for sound alerts and style preview playback.
    var alarmVolume: Float

    /// Snore detection sensitivity (1 = low, 5 = very high). Fixed at 5; stored for
    /// potential future use but not exposed in the UI or read at runtime.
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
        alarmVolume               = 0.60
        snoringDetectionSensitivity = 5
        alarmStyleRaw             = AlarmStyle.classic.rawValue
        pushNotificationEnabled   = true
        soundAlarmEnabled         = true
        pushRepeatEnabled         = true
        pushRepeatIntervalSeconds = 10
    }

    /// Returns existing or creates default settings.
    @MainActor
    static func load(context: ModelContext) -> AlertSettings {
        let descriptor = FetchDescriptor<AlertSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AlertSettings()
        context.insert(settings)
        return settings
    }
}
