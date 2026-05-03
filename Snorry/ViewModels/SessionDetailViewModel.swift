import Foundation
import AVFoundation
import SwiftData
import os.log

// MARK: - AVAudioPlayerDelegate (reference held by view model)
private final class SnorePlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish?()
    }
}

@Observable
@MainActor
final class SessionDetailViewModel {

    let session: SnoreSession

    // Timeline data
    var waveformSamples: [WaveformSample] = []
    var snoreEvents: [SnoreEvent] = []

    // Playback state
    var playingEventID: UUID?
    /// Surface decode / session failures so Replay isn’t a silent no-op while debugging.
    var playbackDiagnostic: String?
    private var player: AVAudioPlayer?
    private var playbackDelegate: SnorePlaybackDelegate?

    private let logger = Logger(subsystem: "app.Snorry", category: "SessionDetail")

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

        do {
            // Tear down recording session cleanly before playback (.playAndRecord can block file playback otherwise).
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try session.setActive(true)

            let p = try AVAudioPlayer(contentsOf: url)
            player = p

            let delegate = SnorePlaybackDelegate()
            delegate.onFinish = { [weak self] in
                Task { @MainActor in
                    self?.playbackDidFinish()
                }
            }
            playbackDelegate = delegate
            p.delegate = delegate

            p.volume = 1.0
            p.prepareToPlay()
            guard p.play() else {
                playbackDiagnostic = "Audio engine did not start playback."
                playbackDidFinish()
                return
            }
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
        player?.stop()
        player?.delegate = nil
        player = nil
        playbackDelegate = nil
        playingEventID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopPlaybackInternal(deactivateSession: Bool) {
        player?.stop()
        player?.delegate = nil
        player = nil
        playbackDelegate = nil
        playingEventID = nil
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: Summary helpers

    var durationString: String {
        guard let dur = session.duration else { return "—" }
        let h = Int(dur) / 3600
        let m = Int(dur) % 3600 / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    var snorePercentString: String {
        String(format: "%.0f%%", session.snoreFraction * 100)
    }
}
