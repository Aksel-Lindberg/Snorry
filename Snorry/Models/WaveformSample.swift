import Foundation
import SwiftData

// MARK: - One-second RMS snapshot used for session-replay waveform
@Model
final class WaveformSample {

    var id: UUID
    var timestamp: Date
    /// dBFS value at this second.
    var dBFS: Float
    /// BRPM value at the time of this sample (0 if not yet available).
    var brpm: Double
    /// Whether snoring was detected at this second.
    var isSnoringActive: Bool

    @Relationship(inverse: \SnoreSession.waveformSamples)
    var session: SnoreSession?

    init(timestamp: Date, dBFS: Float, brpm: Double, isSnoringActive: Bool) {
        self.id = UUID()
        self.timestamp = timestamp
        self.dBFS = dBFS
        self.brpm = brpm
        self.isSnoringActive = isSnoringActive
    }
}
