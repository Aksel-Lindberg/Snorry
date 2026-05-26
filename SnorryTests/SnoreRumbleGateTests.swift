import Testing
import AVFoundation
@testable import Snorry

struct SnoreRumbleGateTests {

    private let sampleRate: Float = 16_000
    private let frameCount = 512

    /// Builds a mono sine buffer at the given frequency and amplitude.
    private func sineBuffer(frequencyHz: Float, amplitude: Float = 0.25) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        for i in 0 ..< frameCount {
            let t = Float(i) / sampleRate
            data[i] = amplitude * sin(2 * Float.pi * frequencyHz * t)
        }
        return buffer
    }

    @Test func lowFrequencyRumblePasses() {
        let buffer = sineBuffer(frequencyHz: 120)
        #expect(SnoreRumbleGate.passes(buffer: buffer))
    }

    @Test func midFrequencyOnlyFails() {
        let buffer = sineBuffer(frequencyHz: 800)
        #expect(!SnoreRumbleGate.passes(buffer: buffer))
    }

    @Test func quietSignalFails() {
        let buffer = sineBuffer(frequencyHz: 120, amplitude: 0.0001)
        #expect(!SnoreRumbleGate.passes(buffer: buffer))
    }

    @Test func lenientConfigAllowsWeakerRumble() {
        var config = SnoreRumbleGate.Config()
        config.ratioThreshold = 1.05
        config.minSignalDBFS = -70
        let buffer = sineBuffer(frequencyHz: 150, amplitude: 0.05)
        #expect(SnoreRumbleGate.passes(buffer: buffer, config: config))
    }
}
