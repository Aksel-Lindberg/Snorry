import Foundation
import AVFoundation
import os.log

@Observable
@MainActor
final class SessionDetailViewModel {

    let session: SnoreSession

    /// All completed bouts, regardless of kind — shown (with labels) in the playback list.
    private(set) var allCompletedEvents: [SnoreEvent] = []

    /// Snoring-classified bouts only — used for Snore Clock and stats.
    private(set) var snoreEvents: [SnoreEvent] = []

    // Playback state
    var playingEventID: UUID?
    /// Surfaces decode / session errors in the UI so replay failures are never silent.
    var playbackDiagnostic: String?

    /// Peak-normalising player: decodes AAC → Float32, boosts gain, plays via AVAudioEngine.
    private let clipPlayer = NormalizingClipPlayer()
    private let logger     = Logger(subsystem: "app.Snorry", category: "SessionDetail")
    /// Tracks whether clip replay has activated the audio session (released in tearDownPlayback).
    private var replaySessionConfigured = false

    /// Loads events off the navigation transition so the History list stays responsive.
    static func prepare(session: SnoreSession) async -> SessionDetailViewModel {
        await Task.yield()
        return SessionDetailViewModel(session: session)
    }

    private init(session: SnoreSession) {
        self.session = session
        let completed = session.events
            .filter { $0.endDate != nil }
            .sorted { $0.startDate < $1.startDate }
        allCompletedEvents = completed
        snoreEvents = completed.filter { $0.soundKind == .snoring }
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

        clipPlayer.onFinish = { [weak self] in
            Task { @MainActor in self?.playbackDidFinish() }
        }

        do {
            try ensureReplaySessionConfigured()
            try clipPlayer.play(url: url)
            playingEventID = event.id
            playbackDiagnostic = nil
        } catch {
            logger.error("Replay failed: \(error.localizedDescription)")
            playbackDiagnostic = error.localizedDescription
            playingEventID = nil
            clipPlayer.stop()
        }
    }

    func stopPlayback() {
        stopPlaybackInternal(deactivateSession: true)
    }

    /// Called when the user leaves session detail — releases replay audio resources.
    func tearDownPlayback() {
        stopPlaybackInternal(deactivateSession: true)
    }

    private func ensureReplaySessionConfigured() throws {
        // Re-apply on every tap so output routing stays correct after monitoring or alarms.
        try AudioSessionManager.shared.configureForClipReplay()
        replaySessionConfigured = true
    }

    private func releaseReplaySession() {
        guard replaySessionConfigured else { return }
        AudioSessionManager.shared.endClipReplaySession(restoreMonitoring: true)
        replaySessionConfigured = false
    }

    private func playbackDidFinish() {
        clipPlayer.stop()
        playingEventID = nil
        AppReviewPrompter.recordCompletedSnoreClipReplay()
        // Keep the replay session warm for the next tap — released in tearDownPlayback().
    }

    private func stopPlaybackInternal(deactivateSession: Bool) {
        clipPlayer.stop()
        playingEventID = nil
        if deactivateSession {
            releaseReplaySession()
        }
    }

    // MARK: Summary helpers

    var durationString: String { session.displayDurationSummary }
}
