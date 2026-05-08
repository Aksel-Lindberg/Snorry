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
    ///
    /// Uses `.default` mode so the system applies full speaker EQ and output processing,
    /// matching the level users hear when previewing sounds in Settings.
    /// The 16 kHz mic analysis rate is achieved by `AudioMonitorService`'s internal
    /// `AVAudioConverter` — no need to pin the hardware I/O to 16 kHz, which would
    /// constrain the output path and reduce alarm loudness.
    func configureForMonitoring() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .duckOthers
            ]
        )
        try session.setPreferredIOBufferDuration(0.02) // ~20 ms latency
        try session.setActive(true)
        // Explicit speaker override — must come after setActive — matches the
        // same call made in configureForClipReplay so both contexts route identically.
        try session.overrideOutputAudioPort(.speaker)
        logger.info("Audio session activated: .playAndRecord / .default + speaker override")
    }

    /// Re-asserts the bottom loudspeaker for alarm playback.
    /// Safe to call while the session is already active (e.g. mid-monitoring).
    func activateSpeakerForAlarm() {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            logger.info("Speaker override re-asserted for alarm")
        } catch {
            logger.error("Failed to override output port for alarm: \(error)")
        }
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
    /// Requests 48 kHz so AAC clips decode at their native rate for full output level.
    func configureForClipReplay() throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
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
