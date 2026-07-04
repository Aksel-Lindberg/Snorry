import Testing
import AVFoundation
@testable import Snorry

struct AudioMathTests {

    // MARK: RMS / dBFS

    @Test func rmsFullScale() {
        // Buffer of 1.0 samples → 0 dBFS
        let samples: [Float] = Array(repeating: 1.0, count: 1024)
        let db = samples.withUnsafeBufferPointer { ptr in
            AudioMath.rmsDBFS(samples: ptr.baseAddress!, count: ptr.count)
        }
        #expect(abs(db) < 0.01, "Full-scale sine should be ~0 dBFS, got \(db)")
    }

    @Test func rmsSilence() {
        let samples: [Float] = Array(repeating: 0.0, count: 1024)
        let db = samples.withUnsafeBufferPointer { ptr in
            AudioMath.rmsDBFS(samples: ptr.baseAddress!, count: ptr.count)
        }
        #expect(db == -160, "Silence should return -160 dBFS, got \(db)")
    }

    @Test func rmsHalfAmplitude() {
        // 0.5 amplitude → -6 dBFS (≈ -6.02)
        let samples: [Float] = Array(repeating: 0.5, count: 1024)
        let db = samples.withUnsafeBufferPointer { ptr in
            AudioMath.rmsDBFS(samples: ptr.baseAddress!, count: ptr.count)
        }
        #expect(abs(db + 6.02) < 0.1, "0.5 amplitude should be ~-6 dBFS, got \(db)")
    }

    // MARK: EMA

    @Test func emaFullAlpha() {
        let result = AudioMath.ema(current: 100, new: 50, alpha: 1.0)
        #expect(result == 50, "α=1 should fully replace")
    }

    @Test func emaZeroAlpha() {
        let result = AudioMath.ema(current: 100, new: 50, alpha: 0.0)
        #expect(result == 100, "α=0 should keep current")
    }

    // MARK: Normalise

    @Test func normalise0dBFS() {
        let n = AudioMath.normalisedLevel(0)
        #expect(n == 1.0, "0 dBFS → 1.0")
    }

    @Test func normaliseFloor() {
        let n = AudioMath.normalisedLevel(-80)
        #expect(n == 0.0, "floor dBFS → 0.0")
    }

    // MARK: Median & BRPM

    @Test func medianOdd() {
        let med = AudioMath.median([3, 1, 2])
        #expect(med == 2, "Median of [1,2,3] = 2")
    }

    @Test func medianEven() {
        let med = AudioMath.median([1, 2, 3, 4])
        #expect(med == 2.5, "Median of [1,2,3,4] = 2.5")
    }

    @Test func brpmTypical() {
        // 15 breaths/min → intervals of 4s → BRPM = 15
        let intervals = Array(repeating: 4.0, count: 10)
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        #expect(brpm != nil && abs(brpm! - 15) < 0.1)
    }

    @Test func brpmFromTimestampsHelper() {
        let timestamps = (0..<4).map { Date(timeIntervalSince1970: Double($0) * 4.0) }
        let brpm = AudioMath.brpm(fromTimestamps: timestamps)
        #expect(brpm != nil && abs(brpm! - 15) < 0.1)
    }

    @Test func brpmFiltersImplausible() {
        // Mix valid (3 s → ~20 BRPM), too-fast (0.1 s), and too-slow (>6 s ⇒ <10 BRPM)
        let intervals = [0.1, 3.0, 3.0, 3.0, 10.0]
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        #expect(brpm != nil && abs(brpm! - 20) < 0.1)
    }

    @Test func brpmRejectsBelow10PerMinute() {
        let intervals = [7.0, 7.0, 7.0] // ~8.57 BRPM
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        #expect(brpm == nil)
    }

    @Test func brpmHarmonicMapsToAudibleBand() {
        // 20/min → ~0.33 Hz; harmonic near 165 Hz (~500×)
        let h = AudioMath.brpmHarmonicHighlightHz(brpm: 20)
        #expect(h != nil && h! >= 85 && h! <= 2800)
    }

    @Test func logSpectrumBandIndexMonotonic() {
        let sr = AudioMonitorService.targetSampleRate
        let hi = AudioMath.logSpectrumBandIndex(freqHz: 3800, bandCount: 52, sampleRate: sr)
        let lo = AudioMath.logSpectrumBandIndex(freqHz: 100, bandCount: 52, sampleRate: sr)
        #expect(hi >= lo && hi < 52)
    }
}
