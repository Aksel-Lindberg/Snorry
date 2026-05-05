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
    /// Seconds of silence before a snore bout is ended/stored (detector gap).
    var clearDelaySeconds: Double

    /// Maximum alarm output level (0–1); playback ramps toward this in 20% steps every 2 s.
    var alarmVolume: Float

    /// Snore detection sensitivity (1 = low, 3 = medium default, 5 = high).
    /// Higher values lower both the onset dB threshold and the classifier confidence
    /// threshold so quieter snores are registered.
    var snoringDetectionSensitivity: Double

    /// Raw value of the selected `AlarmStyle` (stored as Int for SwiftData compatibility).
    var alarmStyleRaw: Int

    /// When false, no push notifications are sent (timing sliders for push are ignored).
    var pushNotificationEnabled: Bool
    /// When false, no in-app sound alarm (volume/style ignored for playback).
    var soundAlarmEnabled: Bool
    /// When true, additional push notifications fire while snoring continues after the first.
    var pushRepeatEnabled: Bool
    /// Seconds between repeated push notifications (only if `pushRepeatEnabled`).
    var pushRepeatIntervalSeconds: Double

    init() {
        notifyDelaySeconds        = 2
        soundAlarmAfterSeconds    = 10
        clearDelaySeconds         = 8
        alarmVolume               = 0.85
        snoringDetectionSensitivity = 3
        alarmStyleRaw             = AlarmStyle.classic.rawValue
        pushNotificationEnabled   = true
        soundAlarmEnabled         = true
        pushRepeatEnabled         = false
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
