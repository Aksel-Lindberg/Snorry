import Foundation
import AVFoundation
import SwiftData

@Observable
@MainActor
final class SessionDetailViewModel {

    let session: SnoreSession

    // Timeline data
    var waveformSamples: [WaveformSample] = []
    var snoreEvents: [SnoreEvent] = []

    // Playback state
    var playingEventID: UUID?
    private var player: AVAudioPlayer?

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
        guard let url = event.audioURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            // Playback at unity gain; loudness follows the Recording + system volume.
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0 // normal AVAudioPlayer level (does not bypass system volume)
            player?.numberOfLoops = 0
            player?.prepareToPlay()
            player?.play()
            playingEventID = event.id
        } catch {
            playingEventID = nil
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingEventID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
