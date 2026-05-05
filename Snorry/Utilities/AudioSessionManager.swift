import AVFoundation
import os.log

// MARK: - Central AVAudioSession configuration
/// All AVAudioSession mutations go through this single point.
final class AudioSessionManager: @unchecked Sendable {

    static let shared = AudioSessionManager()
    private let logger = Logger(subsystem: "app.Snorry", category: "AudioSession")

    private init() {}

    /// Configure the session for simultaneous recording + playback so the alarm
    /// tone can play while the mic tap remains active.
    func configureForMonitoring() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,         // low-latency mic, no AGC
            options: [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .duckOthers
            ]
        )
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.02) // ~20 ms latency
        try session.setActive(true)
        logger.info("Audio session activated: .playAndRecord / .measurement")
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            logger.info("Audio session deactivated")
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }
    }

    /// Configure the session for snore clip replay.
    ///
    /// Uses `.playAndRecord` with `.defaultToSpeaker` — the only reliable way to force
    /// the bottom loudspeaker on iPhone without triggering OSStatus -50.
    /// Resets the 16 kHz sample-rate preference left by `configureForMonitoring` so
    /// the AAC decoder runs at its native rate and outputs at full level.
    func configureForClipReplay() throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        // Reset monitoring sample-rate preference so AAC playback runs at the
        // file's native rate (44.1 / 48 kHz) rather than the 16 kHz capture hint.
        try session.setPreferredSampleRate(48_000)
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker]
        )
        try session.setActive(true)
        // Force bottom loudspeaker explicitly — must come after setActive.
        try session.overrideOutputAudioPort(.speaker)
        logger.info("Audio session configured for clip replay (loudspeaker, 48 kHz)")
    }

    /// Restore automatic output routing after clip replay ends.
    func resetReplayOverrides() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(.none)
        } catch {
            logger.error("Failed to reset output port override: \(error)")
        }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate replay session: \(error)")
        }
        logger.info("Replay audio session deactivated")
    }
}
