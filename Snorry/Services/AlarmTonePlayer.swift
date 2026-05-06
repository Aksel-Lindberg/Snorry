import AVFoundation
import os.log

// MARK: - Alarm tone styles

enum AlarmStyle: Int, Codable, CaseIterable, Sendable {
    case gentle  = 0
    case classic = 1
    case alert   = 2

    var displayName: String {
        switch self {
        case .gentle:  return "Gentle"
        case .classic: return "Classic"
        case .alert:   return "Alert"
        }
    }

    var subtitle: String {
        switch self {
        case .gentle:  return "440 Hz · soft slow pulse"
        case .classic: return "880 Hz · steady double-tone"
        case .alert:   return "1 kHz · triple burst"
        }
    }
}

// MARK: - Synthesises and plays a looping alarm tone
/// No binary audio assets required — everything is generated in memory.
final class AlarmTonePlayer: @unchecked Sendable {

    private let engine     = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixerNode: AVAudioMixerNode

    private var toneBuffer: AVAudioPCMBuffer?
    private var isRunning  = false
    private(set) var style: AlarmStyle = .classic

    private var targetVolume: Float  = 0
    private var currentVolume: Float = 0
    private let rampDuration: Float  = 1.2   // seconds for volume ramp
    private var rampTimer: Timer?

    private let logger = Logger(subsystem: "app.Snorry", category: "AlarmTone")

    private static let sampleRate: Double = 44_100
    /// Global loudness boost for synthesized alarms.
    /// Values > 1 increase perceived loudness before soft-clipping.
    private static let outputDrive: Double = 1.8

    init() {
        mixerNode = engine.mainMixerNode
        engine.attach(playerNode)
        toneBuffer = Self.synthesize(style: .classic)
        if let toneBuffer {
            configurePlayerConnection(for: toneBuffer.format)
        } else {
            configurePlayerConnection(for: Self.makeFormat())
        }
    }

    // MARK: Style selection

    /// Re-synthesises the internal buffer for the chosen style.
    /// Safe to call before or after `play()`; a running engine is restarted.
    func setStyle(_ newStyle: AlarmStyle) {
        guard newStyle != style else { return }
        style = newStyle
        let wasRunning = isRunning
        if wasRunning { stop() }
        toneBuffer = Self.synthesize(style: newStyle) ?? Self.synthesize(style: .classic)
        if let toneBuffer {
            configurePlayerConnection(for: toneBuffer.format)
        } else {
            configurePlayerConnection(for: Self.makeFormat())
        }
        if wasRunning { startEngine() }
    }

    // MARK: Playback control

    func play(volume: Float) {
        targetVolume = volume
        if !isRunning { startEngine() }
        startRamp()
    }

    /// Hard-stop with no fade — use when snoring ends.
    func stop() {
        rampTimer?.invalidate()
        rampTimer = nil
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        isRunning     = false
        currentVolume = 0
        mixerNode.outputVolume = 0
    }

    /// Smooth fade-out — kept for optional use.
    func fadeOut() {
        targetVolume = 0
        startRamp { [weak self] in self?.stopEngine() }
    }

    // MARK: Private engine helpers

    private func startEngine() {
        do {
            try engine.start()
            isRunning = true
            scheduleLoop()
        } catch {
            logger.error("Alarm engine start failed: \(error)")
        }
    }

    private func stopEngine() {
        playerNode.stop()
        engine.stop()
        isRunning     = false
        currentVolume = 0
    }

    private func scheduleLoop() {
        guard let buffer = toneBuffer, isRunning else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        if !playerNode.isPlaying { playerNode.play() }
    }

    /// Keeps player-node output format aligned with the currently selected buffer format.
    /// This avoids AVAudioPlayerNode schedule crashes when switching between mono synth tones
    /// and stereo bundled clips.
    private func configurePlayerConnection(for format: AVAudioFormat) {
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: mixerNode, format: format)
    }

    private func startRamp(completion: (() -> Void)? = nil) {
        rampTimer?.invalidate()
        let stepInterval: TimeInterval = 0.05
        let totalSteps = rampDuration / Float(stepInterval)

        rampTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let delta = (self.targetVolume - self.currentVolume) / totalSteps
            self.currentVolume = max(0, min(1, self.currentVolume + delta))
            DispatchQueue.main.async { self.mixerNode.outputVolume = self.currentVolume }
            if abs(self.currentVolume - self.targetVolume) < 0.01 {
                timer.invalidate()
                self.rampTimer = nil
                completion?()
            }
        }
    }

    // MARK: Format

    private static func makeFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    // MARK: Synthesis dispatcher

    private static func synthesize(style: AlarmStyle) -> AVAudioPCMBuffer? {
        switch style {
        case .gentle:  return synthesizeGentle()
        case .classic: return synthesizeClassic()
        case .alert:   return synthesizeAlert()
        }
    }

    /// Cosine-shaped attack/release envelope; `pos` and `duration` in samples.
    private static func cosEnv(
        pos: Int,
        duration: Int,
        attackFrac: Double = 0.08,
        releaseFrac: Double = 0.08
    ) -> Double {
        let atk = max(1, Int(Double(duration) * attackFrac))
        let rel = max(1, Int(Double(duration) * releaseFrac))
        if pos < atk { return 0.5 * (1 - cos(.pi * Double(pos) / Double(atk))) }
        if pos > duration - rel { return 0.5 * (1 - cos(.pi * Double(duration - pos) / Double(rel))) }
        return 1.0
    }

    /// Applies loudness drive with soft clipping to keep samples in [-1, 1].
    private static func driven(_ sample: Double, extraDrive: Double = 1.0) -> Float {
        let boosted = sample * outputDrive * extraDrive
        let clipped = tanh(boosted)
        return Float(max(-1.0, min(1.0, clipped)))
    }

    // MARK: Gentle — 440/330 Hz, 1.5 s on / 0.5 s off

    private static func synthesizeGentle() -> AVAudioPCMBuffer? {
        let rate    = sampleRate
        let onDur   = 1.5
        let total   = AVAudioFrameCount(rate * 2.0)
        let onCount = Int(rate * onDur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: makeFormat(), frameCapacity: total),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total
        for idx in 0..<Int(total) {
            guard idx < onCount else { data[idx] = 0; continue }
            let time = Double(idx) / rate
            let wave = (sin(2 * .pi * 440 * time) + sin(2 * .pi * 330 * time)) * 0.5
            data[idx] = driven(wave * cosEnv(pos: idx, duration: onCount))
        }
        return buf
    }

    // MARK: Classic — 880/660 Hz, 0.45 s on / 0.55 s off

    private static func synthesizeClassic() -> AVAudioPCMBuffer? {
        let rate    = sampleRate
        let onDur   = 0.45
        let total   = AVAudioFrameCount(rate * 1.0)
        let onCount = Int(rate * onDur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: makeFormat(), frameCapacity: total),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total
        for idx in 0..<Int(total) {
            guard idx < onCount else { data[idx] = 0; continue }
            let time = Double(idx) / rate
            let wave = (sin(2 * .pi * 880 * time) + sin(2 * .pi * 660 * time)) * 0.5
            data[idx] = driven(wave * cosEnv(pos: idx, duration: onCount))
        }
        return buf
    }

    // MARK: Alert — 1000/750 Hz, three 0.18 s beeps + 0.56 s pause

    private static func synthesizeAlert() -> AVAudioPCMBuffer? {
        let rate     = sampleRate
        let beepDur  = 0.18
        let gapDur   = 0.10
        let pauseDur = 0.56
        let cycleDur = (beepDur + gapDur) * 3 + pauseDur  // ≈ 1.40 s
        let total    = AVAudioFrameCount(rate * cycleDur)
        let beepN    = Int(rate * beepDur)
        let stepN    = Int(rate * (beepDur + gapDur))
        guard let buf = AVAudioPCMBuffer(pcmFormat: makeFormat(), frameCapacity: total),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total
        for idx in 0..<Int(total) {
            let burstIndex = idx / stepN
            let posInStep  = idx % stepN
            guard burstIndex < 3, posInStep < beepN else { data[idx] = 0; continue }
            let time = Double(idx) / rate
            let wave = (sin(2 * .pi * 1000 * time) + sin(2 * .pi * 750 * time)) * 0.5
            data[idx] = driven(
                wave * cosEnv(
                    pos: posInStep,
                    duration: beepN,
                    attackFrac: 0.10,
                    releaseFrac: 0.10
                )
            )
        }
        return buf
    }

}
