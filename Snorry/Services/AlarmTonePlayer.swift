import AVFoundation
import os.log

// MARK: - Alarm tone styles

enum AlarmStyle: Int, Codable, CaseIterable, Sendable {
    case gentle  = 0
    case classic = 1
    case alert   = 2
    case urgent  = 3
    case siren   = 4
    case extreme = 5
    case nudge   = 6
    case pianoLove = 7
    case sideSoftFemaleVoice = 8
    case sideSoftVoiceAlert = 9
    case marimbaSoft = 10
    case screamingWoman = 11
    case shoutingWoman = 12
    case catMeowSoft = 13
    case dogBarkSoft = 14
    case stopSnoringSoftFemale = 15
    case firstLightOnPier = 16

    var displayName: String {
        switch self {
        case .gentle:  return "Gentle"
        case .classic: return "Classic"
        case .alert:   return "Alert"
        case .urgent:  return "Urgent"
        case .siren:   return "Siren"
        case .extreme: return "Extreme"
        case .nudge:   return "Soft Nudge"
        case .pianoLove: return "I Love You Piano"
        case .sideSoftFemaleVoice: return "Move to Side (Female)"
        case .sideSoftVoiceAlert: return "Move to Side (Soft)"
        case .marimbaSoft: return "Soft Marimba"
        case .screamingWoman: return "Screaming Woman"
        case .shoutingWoman: return "Shouting Woman"
        case .catMeowSoft: return "Soft Cat Meow"
        case .dogBarkSoft: return "Soft Dog Bark"
        case .stopSnoringSoftFemale: return "Stop Snoring (Female)"
        case .firstLightOnPier: return "First Light on the Pier"
        }
    }

    var subtitle: String {
        switch self {
        case .gentle:  return "440 Hz · soft slow pulse"
        case .classic: return "880 Hz · steady double-tone"
        case .alert:   return "1 kHz · triple burst"
        case .urgent:  return "1.2 kHz · rapid staccato"
        case .siren:   return "800–1400 Hz · rising sweep"
        case .extreme: return "1.6 kHz · max-intensity rapid burst"
        case .nudge:   return "Recorded soft position nudge"
        case .pianoLove: return "Recorded piano clip"
        case .sideSoftFemaleVoice: return "Recorded female voice prompt"
        case .sideSoftVoiceAlert: return "Recorded soft voice alert"
        case .marimbaSoft: return "Recorded marimba clip"
        case .screamingWoman: return "Recorded loud voice clip"
        case .shoutingWoman: return "Recorded shouting voice clip"
        case .catMeowSoft: return "Recorded cat meow clip"
        case .dogBarkSoft: return "Recorded dog bark clip"
        case .stopSnoringSoftFemale: return "Recorded female voice prompt"
        case .firstLightOnPier: return "Recorded piano track"
        }
    }

    var bundledClipName: String? {
        switch self {
        case .nudge: return "soft_snore_position_nudge_alert"
        case .pianoLove: return "i_love_you_short_piano_clip"
        case .sideSoftFemaleVoice: return "move_to_side_soft_female_voice"
        case .sideSoftVoiceAlert: return "move_to_side_soft_voice_alert"
        case .marimbaSoft: return "nice_soft_marimba_clip"
        case .screamingWoman: return "screaming_woman_clip"
        case .shoutingWoman: return "shouting_woman_clip"
        case .catMeowSoft: return "soft_cat_meow_clip"
        case .dogBarkSoft: return "soft_dog_bark_clip"
        case .stopSnoringSoftFemale: return "stop_snoring_soft_female_voice"
        case .firstLightOnPier: return "first_light_on_the_pier"
        default: return nil
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
    private static let bundledClipExtension = "mp3"

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
        if let bundledClipName = style.bundledClipName {
            return loadBundledClip(named: bundledClipName)
        }
        switch style {
        case .gentle:  return synthesizeGentle()
        case .classic: return synthesizeClassic()
        case .alert:   return synthesizeAlert()
        case .urgent:  return synthesizeUrgent()
        case .siren:   return synthesizeSiren()
        case .extreme: return synthesizeExtreme()
        case .nudge,
                .pianoLove,
                .sideSoftFemaleVoice,
                .sideSoftVoiceAlert,
                .marimbaSoft,
                .screamingWoman,
                .shoutingWoman,
                .catMeowSoft,
                .dogBarkSoft,
                .stopSnoringSoftFemale,
                .firstLightOnPier:
            return nil
        }
    }

    private static func loadBundledClip(named name: String) -> AVAudioPCMBuffer? {
        guard let fileURL = Bundle.main.url(forResource: name, withExtension: bundledClipExtension) else {
            return nil
        }
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: audioFile.processingFormat,
                    frameCapacity: frameCount
                  ) else {
                return nil
            }
            try audioFile.read(into: buffer)
            return buffer
        } catch {
            return nil
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

    // MARK: Urgent — 1200/900 Hz, rapid 0.15 s on / 0.10 s off

    private static func synthesizeUrgent() -> AVAudioPCMBuffer? {
        let rate    = sampleRate
        let onDur   = 0.15
        let total   = AVAudioFrameCount(rate * 0.25)
        let onCount = Int(rate * onDur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: makeFormat(), frameCapacity: total),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total
        for idx in 0..<Int(total) {
            guard idx < onCount else { data[idx] = 0; continue }
            let time = Double(idx) / rate
            let wave = (sin(2 * .pi * 1200 * time) + sin(2 * .pi * 900 * time)) * 0.5
            data[idx] = driven(
                wave * cosEnv(
                    pos: idx,
                    duration: onCount,
                    attackFrac: 0.05,
                    releaseFrac: 0.05
                )
            )
        }
        return buf
    }

    // MARK: Siren — frequency sweep 800→1400 Hz over 1.0 s, then 0.3 s silence

    private static func synthesizeSiren() -> AVAudioPCMBuffer? {
        let rate     = sampleRate
        let sweepDur = 1.0
        let silDur   = 0.3
        let total    = AVAudioFrameCount(rate * (sweepDur + silDur))
        let sweepN   = Int(rate * sweepDur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: makeFormat(), frameCapacity: total),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total
        // Integrate instantaneous phase to avoid discontinuities at the start of silence.
        var phase = 0.0
        for idx in 0..<Int(total) {
            guard idx < sweepN else { data[idx] = 0; continue }
            let frac = Double(idx) / Double(sweepN)
            let freq = 800.0 + 600.0 * frac
            phase   += 2 * .pi * freq / rate
            let wave = sin(phase)
            data[idx] = driven(
                wave * cosEnv(
                    pos: idx,
                    duration: sweepN,
                    attackFrac: 0.04,
                    releaseFrac: 0.08
                )
            )
        }
        return buf
    }

    // MARK: Extreme — 1600/1200 Hz + harmonic, rapid 0.14 s bursts for maximum urgency

    private static func synthesizeExtreme() -> AVAudioPCMBuffer? {
        let rate     = sampleRate
        let beepDur  = 0.14
        let gapDur   = 0.06
        let pauseDur = 0.20
        let cycleDur = (beepDur + gapDur) * 4 + pauseDur
        let total    = AVAudioFrameCount(rate * cycleDur)
        let beepN    = Int(rate * beepDur)
        let stepN    = Int(rate * (beepDur + gapDur))

        guard let buf = AVAudioPCMBuffer(pcmFormat: makeFormat(), frameCapacity: total),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = total

        for idx in 0..<Int(total) {
            let burstIndex = idx / stepN
            let posInStep  = idx % stepN
            guard burstIndex < 4, posInStep < beepN else { data[idx] = 0; continue }
            let time = Double(idx) / rate
            // Add a light third harmonic for stronger speaker presence.
            let wave = (sin(2 * .pi * 1600 * time)
                        + sin(2 * .pi * 1200 * time)
                        + 0.35 * sin(2 * .pi * 2400 * time)) / 2.35
            data[idx] = driven(
                wave * cosEnv(
                    pos: posInStep,
                    duration: beepN,
                    attackFrac: 0.03,
                    releaseFrac: 0.04
                ),
                extraDrive: 1.35
            )
        }
        return buf
    }
}
