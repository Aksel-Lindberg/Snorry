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

    @Test func speechDominanceRejectsSleepTalkingLikeSpectrum() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let frameCount = 512
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let data = buffer.floatChannelData?[0] else { return }

        // Low rumble plus strong mid speech-like energy — should not pass snore gate.
        for i in 0 ..< frameCount {
            let t = Float(i) / 16_000
            data[i] = 0.12 * sin(2 * Float.pi * 120 * t) + 0.22 * sin(2 * Float.pi * 900 * t)
        }
        #expect(!SnoreRumbleGate.passes(buffer: buffer))
    }
}
