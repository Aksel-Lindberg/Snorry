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

    init() {
        notifyDelaySeconds        = 2
        soundAlarmAfterSeconds    = 15
        clearDelaySeconds         = 8
        alarmVolume               = 0.85
        snoringDetectionSensitivity = 3
        alarmStyleRaw             = AlarmStyle.classic.rawValue
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
