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
    /// Relative path to the AAC clip file under Application Support/SnoreClips/.
    var audioRelativePath: String?

    @Relationship(inverse: \SnoreSession.events)
    var session: SnoreSession?

    init(id: UUID = UUID(), startDate: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.brpm = 0
        self.peakDB = -160
    }

    var duration: TimeInterval? {
        guard let end = endDate else { return nil }
        return end.timeIntervalSince(startDate)
    }

    /// Resolved URL for the audio clip, if it exists.
    var audioURL: URL? {
        guard let rel = audioRelativePath else { return nil }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent(rel)
    }
}
