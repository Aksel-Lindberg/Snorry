import Foundation
import SwiftData

// MARK: - Sound category for a detected bout
/// Used to distinguish confirmed snoring from background noise and sleep talking
/// when the session included a lock/background recording period.
/// Defaults to `.snoring` so foreground-only sessions and legacy rows are unchanged.
enum SoundEventKind: Int, Codable, Sendable {
    case snoring     = 0
    case sleepTalking = 1
    case environment = 2

    var displayName: String {
        switch self {
        case .snoring:      return "Snoring"
        case .sleepTalking: return "Sleep Talking"
        case .environment:  return "Environment"
        }
    }

    var systemImage: String {
        switch self {
        case .snoring:      return "zzz"
        case .sleepTalking: return "bubble.left"
        case .environment:  return "waveform"
        }
    }
}

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
    /// Strongest frequency in the snore rumble band (**measured** from the saved AAC clip via FFT).
    /// Used for timbre / person comparison; 0 until background analysis finishes or if the clip is unusable.
    var spectralPeakHz: Double
    /// Relative path to the AAC clip file under Application Support/SnoreClips/.
    var audioRelativePath: String?
    /// Raw storage for `SoundEventKind` — set to `.snoring` by default so existing rows
    /// and foreground-only sessions require no migration.
    var soundKindRaw: Int

    @Relationship(inverse: \SnoreSession.events)
    var session: SnoreSession?

    /// Typed accessor; writes through `soundKindRaw`.
    var soundKind: SoundEventKind {
        get { SoundEventKind(rawValue: soundKindRaw) ?? .snoring }
        set { soundKindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), startDate: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.brpm = 0
        self.peakDB = -160
        self.avgDB = -160
        self.rumbleFrequencyHz = 0
        self.spectralPeakHz = 0
        self.soundKindRaw = SoundEventKind.snoring.rawValue
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
