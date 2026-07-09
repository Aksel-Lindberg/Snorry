import Foundation
import SwiftData

// MARK: - Settings change snapshot for analytics annotation
/// Appended whenever the user saves a change to push/alarm settings.
/// Used to annotate the analytics trendline with markers showing when settings changed.
@Model
final class AlertSettingsChange {

    var timestamp: Date

    // Push notification settings
    var pushNotificationEnabled: Bool
    var notifyDelaySeconds: Double
    var pushRepeatEnabled: Bool
    var pushRepeatIntervalSeconds: Double

    // Sound alarm settings
    var soundAlarmEnabled: Bool
    var soundAlarmAfterSeconds: Double
    var alarmStyleRaw: Int

    init(
        timestamp: Date = Date(),
        pushNotificationEnabled: Bool,
        notifyDelaySeconds: Double,
        pushRepeatEnabled: Bool,
        pushRepeatIntervalSeconds: Double,
        soundAlarmEnabled: Bool,
        soundAlarmAfterSeconds: Double,
        alarmStyleRaw: Int
    ) {
        self.timestamp = timestamp
        self.pushNotificationEnabled = pushNotificationEnabled
        self.notifyDelaySeconds = notifyDelaySeconds
        self.pushRepeatEnabled = pushRepeatEnabled
        self.pushRepeatIntervalSeconds = pushRepeatIntervalSeconds
        self.soundAlarmEnabled = soundAlarmEnabled
        self.soundAlarmAfterSeconds = soundAlarmAfterSeconds
        self.alarmStyleRaw = alarmStyleRaw
    }

    /// Compact human-readable summary of the key push/alarm configuration for legend display.
    var summaryLabel: String {
        var parts: [String] = []
        if pushNotificationEnabled {
            parts.append("Push ON · after \(formatSeconds(AlertTimingDefaults.notifyDelaySeconds))")
            if pushRepeatEnabled {
                parts.append("repeat with sound alarm")
            }
        } else {
            parts.append("Push OFF")
        }
        if soundAlarmEnabled {
            let style = AlarmStyle(rawValue: alarmStyleRaw)?.displayName ?? "Alarm"
            parts.append("\(style) · after \(formatSeconds(AlertTimingDefaults.soundAlarmAfterSeconds))")
        } else {
            parts.append("Alarm OFF")
        }
        return parts.joined(separator: "  ·  ")
    }

    private func formatSeconds(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
    }
}
