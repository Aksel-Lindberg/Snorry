import Foundation
import SwiftData

// MARK: - A single continuous snoring episode within a session
@Model
final class SnoreEvent {

    var id: UUID
    var startDate: Date
    var endDate: Date?
    /// BRPM calculated over this event's onset timestamps.
    var brpm: Double
    /// Peak dBFS during this event.
    var peakDB: Float
    /// Arithmetic mean dBFS across all classifier-active ticks during this event.
    var avgDB: Float
    /// Lowest harmonic of the breath tempo that falls in the live-spectrum snore band
    /// (same value shown as the red marker on the Live Power Spectrum during monitoring).
    /// 0 when not available.
    var rumbleFrequencyHz: Double
    /// Relative path to the AAC clip file under Application Support/SnoreClips/.
    var audioRelativePath: String?

    @Relationship(inverse: \SnoreSession.events)
    var session: SnoreSession?

    init(id: UUID = UUID(), startDate: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.brpm = 0
        self.peakDB = -160
        self.avgDB = -160
        self.rumbleFrequencyHz = 0
    }

    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    /// Resolved URL for the audio clip, if a path was stored.
    var audioURL: URL? {
        guard let rel = audioRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rel.isEmpty else { return nil }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(rel)
    }

    /// URL only when the AAC file exists on disk (used for replay UI + playback).
    var playbackURL: URL? {
        guard let url = audioURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.standardizedFileURL
    }
}
