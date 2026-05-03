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
        // 15 snores/min → intervals of 4s → BRPM = 15
        let intervals = Array(repeating: 4.0, count: 10)
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        #expect(brpm != nil && abs(brpm! - 15) < 0.1)
    }

    @Test func brpmFiltersImplausible() {
        // Mix valid (3s) with implausibly short (0.1s) and long (10s)
        let intervals = [0.1, 3.0, 3.0, 3.0, 10.0]
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        // Expect ~20 BRPM from valid 3s intervals only
        #expect(brpm != nil && abs(brpm! - 20) < 0.1)
    }
}
