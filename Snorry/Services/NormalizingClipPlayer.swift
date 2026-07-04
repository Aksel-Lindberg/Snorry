import AVFoundation
import Accelerate

// MARK: - Peak-normalised clip player
/// Decodes an AAC/M4A file into a Float32 PCM buffer, measures its peak sample,
/// scales all samples so the peak lands at –1 dBFS (max gain +18 dB), then plays
/// back through AVAudioEngine.
///
/// This lets quiet snore recordings be heard at a natural perceived volume without
/// any server-side processing. AVAudioPlayer.volume is capped at 1.0 and cannot
/// amplify below-unity recordings; AVAudioEngine has no such restriction.
final class NormalizingClipPlayer: @unchecked Sendable {

    /// Called on the main queue when playback finishes naturally.
    var onFinish: (() -> Void)?

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// Maximum linear gain (+18 dB ≈ ×8) to prevent near-silent clips from becoming
    /// uncomfortably loud while still giving a strong boost to typical snore levels.
    private static let maxGain: Float   = 8.0
    /// Target peak after normalisation (–1 dBFS).
    private static let targetPeak: Float = 0.891

    init() {
        engine.attach(playerNode)
    }

    // MARK: - Playback

    /// Loads `url`, peak-normalises the decoded buffer, and starts playback.
    /// Throws on any I/O or AVAudioEngine error.
    func play(url: URL) throws {
        stop()

        let file       = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else {
            throw NSError(
                domain: "app.Snorry", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Recorded clip is empty."]
            )
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: frameCount) else {
            throw NSError(
                domain: "app.Snorry", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate normalisation buffer."]
            )
        }
        try file.read(into: buffer)
        buffer.frameLength = frameCount

        applyPeakNormalisation(to: buffer)

        // Route through the output node (Apple's simple-playback pattern) so the graph
        // stays connected even when the main mixer link was torn down by a prior stop.
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.outputNode, format: buffer.format)

        engine.prepare()
        try engine.start()

        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async { self?.didFinish() }
        }
        playerNode.play()
    }

    /// Stops playback immediately (no fade).
    func stop() {
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        // Do not call `engine.reset()` — it severs the mixer→output connection and
        // matches AlarmTonePlayer, which keeps the graph intact between plays.
    }

    // MARK: - Private

    private func didFinish() {
        stop()
        onFinish?()
    }

    /// Finds the peak magnitude across all channels with `vDSP_maxmgv`, then
    /// multiplies every sample by the normalisation gain with `vDSP_vsmul`.
    private func applyPeakNormalisation(to buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount   = vDSP_Length(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Pass 1 — find peak magnitude across all channels.
        var peak: Float = 0
        for channel in 0..<channelCount {
            var channelPeak: Float = 0
            vDSP_maxmgv(channelData[channel], 1, &channelPeak, frameCount)
            if channelPeak > peak { peak = channelPeak }
        }

        // Skip gain if clip is effectively silent.
        guard peak > 0.001 else { return }

        var gain = min(Self.targetPeak / peak, Self.maxGain)

        // Pass 2 — scale all samples by gain in-place.
        for channel in 0..<channelCount {
            vDSP_vsmul(channelData[channel], 1, &gain, channelData[channel], 1, frameCount)
        }
    }
}
