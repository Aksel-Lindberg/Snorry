import Foundation
import Testing
@testable import Snorry

struct SnoreClipSpectralAnalyzerTests {

    @Test func peakHzFindsSyntheticSine() {
        let sr = 48_000.0
        let targetHz = 220.0
        let duration = 2.0
        let count = Int(sr * duration)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            samples[i] = Float(sin(2 * .pi * targetHz * t))
        }
        let peak = SnoreClipSpectralAnalyzer.peakHz(monoSamples: samples, sampleRate: sr)
        #expect(peak != nil)
        #expect(abs(peak! - targetHz) < 12, "bin resolution ~\(48000/4096) Hz; got \(peak!)")
    }
}
