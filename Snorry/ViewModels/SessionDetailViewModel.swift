import Foundation
import AVFoundation
import SwiftData
import os.log

@Observable
@MainActor
final class SessionDetailViewModel {

    let session: SnoreSession

    // Timeline data
    var waveformSamples: [WaveformSample] = []
    var snoreEvents: [SnoreEvent] = []

    // Playback state
    var playingEventID: UUID?
    /// Surfaces decode / session errors in the UI so replay failures are never silent.
    var playbackDiagnostic: String?

    /// Peak-normalising player: decodes AAC → Float32, boosts gain, plays via AVAudioEngine.
    private let clipPlayer = NormalizingClipPlayer()
    private let logger     = Logger(subsystem: "app.Snorry", category: "SessionDetail")

    init(session: SnoreSession) {
        self.session = session
        waveformSamples = session.waveformSamples
            .sorted { $0.timestamp < $1.timestamp }
        snoreEvents = session.events
            .filter { $0.endDate != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: Playback

    func togglePlayback(of event: SnoreEvent) {
        if playingEventID == event.id {
            stopPlayback()
            return
        }

        guard let url = event.playbackURL else {
            playbackDiagnostic = event.audioRelativePath != nil
                ? "Recorded file missing on disk."
                : "No audio path stored for this event."
            logger.warning("Replay skipped — path=\(String(describing: event.audioRelativePath))")
            return
        }

        stopPlaybackInternal(deactivateSession: false)

        // Wire finish callback before play() so it's set even if play() throws.
        clipPlayer.onFinish = { [weak self] in
            Task { @MainActor in self?.playbackDidFinish() }
        }

        do {
            // Force loudspeaker and reset monitoring's 16 kHz preferred sample rate.
            try AudioSessionManager.shared.configureForClipReplay()
            // Decode, peak-normalise (up to +18 dB), then start AVAudioEngine playback.
            try clipPlayer.play(url: url)
            playingEventID = event.id
            playbackDiagnostic = nil
        } catch {
            logger.error("Replay failed: \(error.localizedDescription)")
            playbackDiagnostic = error.localizedDescription
            playbackDidFinish()
        }
    }

    func stopPlayback() {
        stopPlaybackInternal(deactivateSession: true)
    }

    private func playbackDidFinish() {
        clipPlayer.stop()
        playingEventID = nil
        // Restore automatic output routing and deactivate the replay session.
        AudioSessionManager.shared.resetReplayOverrides()
    }

    private func stopPlaybackInternal(deactivateSession: Bool) {
        clipPlayer.stop()
        playingEventID = nil
        if deactivateSession {
            AudioSessionManager.shared.resetReplayOverrides()
        }
    }

    // MARK: Summary helpers

    var durationString: String {
        guard let dur = session.duration else { return "—" }
        let hours   = Int(dur) / 3600
        let minutes = Int(dur) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var snorePercentString: String {
        String(format: "%.0f%%", session.snoreFraction * 100)
    }
}
