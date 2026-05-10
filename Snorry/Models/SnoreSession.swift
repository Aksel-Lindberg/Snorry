import Foundation
import SwiftData

// MARK: - A single sleep monitoring session
@Model
final class SnoreSession {

    var id: UUID
    var startDate: Date
    var endDate: Date?

    /// Total duration of all snore events in this session (seconds).
    var totalSnoreDuration: Double
    /// Number of distinct snore events detected.
    var eventCount: Int
    /// Average BRPM across all events that had enough data.
    var avgBRPM: Double
    /// Peak dBFS recorded during the session.
    var peakDB: Float

    // MARK: Alert snapshot (captured at session start; nil on legacy rows)
    /// Whether push notifications were enabled when monitoring began.
    var snapshotPushEnabled: Bool?
    /// Whether the sound alarm was enabled when monitoring began.
    var snapshotSoundEnabled: Bool?
    /// Raw value of `AlarmStyle` active when monitoring began.
    var snapshotAlarmStyleRaw: Int?

    @Relationship(deleteRule: .cascade)
    var events: [SnoreEvent]

    @Relationship(deleteRule: .cascade)
    var waveformSamples: [WaveformSample]

    init(id: UUID = UUID(), startDate: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.totalSnoreDuration = 0
        self.eventCount = 0
        self.avgBRPM = 0
        self.peakDB = -160
        self.events = []
        self.waveformSamples = []
    }

    /// Computed duration in seconds (nil if session still active).
    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    /// Fraction of time spent snoring (0–1).
    var snoreFraction: Double {
        guard let dur = duration, dur > 0 else { return 0 }
        return min(1, totalSnoreDuration / dur)
    }

    // MARK: Display strings (Monitor card + session detail — avoids spinning up `SessionDetailViewModel`)

    /// e.g. `"6h 57m"` or `"42m"`.
    var displayDurationSummary: String {
        guard let dur = duration else { return "—" }
        let hours = Int(dur) / 3600
        let minutes = Int(dur) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// Whole‑percent snoring share for UI labels.
    var displaySnoringPercent: String {
        String(format: "%.0f%%", snoreFraction * 100)
    }

    /// Sum of all snore‑bout durations (`totalSnoreDuration`), for Monitor “Last Session”.
    var displayTotalSnoreTime: String {
        Self.formatSnoreDuration(seconds: totalSnoreDuration)
    }

    /// Mean snore‑bout length across counted events.
    var displayAvgSnoreTimePerEvent: String {
        guard eventCount > 0, totalSnoreDuration > 0 else { return "—" }
        let avg = totalSnoreDuration / Double(eventCount)
        return Self.formatSnoreDuration(seconds: avg)
    }

    /// Compact duration from stored seconds (snore totals / averages).
    private static func formatSnoreDuration(seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total)s"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
