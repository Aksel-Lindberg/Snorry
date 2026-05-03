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
}
