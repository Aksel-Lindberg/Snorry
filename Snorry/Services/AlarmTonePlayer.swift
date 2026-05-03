import AVFoundation
import os.log

// MARK: - Synthesises and plays a pulsing 2-tone alarm with smooth volume ramps
/// No binary audio assets required — everything is generated in memory.
final class AlarmTonePlayer: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixerNode: AVAudioMixerNode

    private var toneBuffer: AVAudioPCMBuffer?
    private var isRunning = false

    private var targetVolume: Float = 0
    private var currentVolume: Float = 0
    private let rampDuration: Float = 1.5   // seconds
    private var rampTimer: Timer?

    private let logger = Logger(subsystem: "app.Snorry", category: "AlarmTone")

    private static let sampleRate: Double = 44_100
    private static let toneHz1: Double    = 880   // A5
    private static let toneHz2: Double    = 660   // E5
    private static let pulseDuration: Double = 1.0 // one on/off cycle

    init() {
        mixerNode = engine.mainMixerNode
        engine.attach(playerNode)
        engine.connect(playerNode, to: mixerNode, format: Self.makeFormat())
        toneBuffer = Self.synthesizeTone()
    }

    // MARK: Playback control

    func play(volume: Float) {
        targetVolume = volume
        if !isRunning { startEngine() }
        startRamp()
    }

    func fadeOut() {
        targetVolume = 0
        startRamp(completion: { [weak self] in
            self?.stopEngine()
        })
    }

    func stop() {
        rampTimer?.invalidate()
        rampTimer = nil
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        isRunning = false
        currentVolume = 0
        mixerNode.outputVolume = 0
    }

    // MARK: Private

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
        isRunning = false
        currentVolume = 0
    }

    private func scheduleLoop() {
        guard let buffer = toneBuffer, isRunning else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        if !playerNode.isPlaying { playerNode.play() }
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

            let done = abs(self.currentVolume - self.targetVolume) < 0.01
            if done {
                timer.invalidate()
                self.rampTimer = nil
                completion?()
            }
        }
    }

    // MARK: Tone synthesis

    private static func makeFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    /// Returns one full pulse cycle: 0.5 s tone + 0.5 s silence (loopable).
    private static func synthesizeTone() -> AVAudioPCMBuffer? {
        let format = makeFormat()
        let totalFrames = AVAudioFrameCount(sampleRate * pulseDuration)
        let toneFrames  = AVAudioFrameCount(sampleRate * 0.45)   // 45 % on
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else { return nil }
        buffer.frameLength = totalFrames

        guard let data = buffer.floatChannelData?[0] else { return nil }
        let freq1 = toneHz1
        let freq2 = toneHz2
        let sr = sampleRate

        for i in 0..<Int(totalFrames) {
            if i < Int(toneFrames) {
                // Blend two sine waves, soft attack/release envelope
                let t = Double(i) / sr
                let env: Double
                let attack = 0.05 * Double(toneFrames) / sr
                let release = 0.05 * Double(toneFrames) / sr
                let tNorm = t / (Double(toneFrames) / sr)
                if tNorm < attack / (Double(toneFrames) / sr) {
                    env = tNorm / (attack / (Double(toneFrames) / sr))
                } else if tNorm > 1 - release / (Double(toneFrames) / sr) {
                    env = (1 - tNorm) / (release / (Double(toneFrames) / sr))
                } else {
                    env = 1.0
                }
                let sine = (sin(2 * .pi * freq1 * t) + sin(2 * .pi * freq2 * t)) * 0.5
                data[i] = Float(sine * env * 0.8)
            } else {
                data[i] = 0
            }
        }
        return buffer
    }
}
