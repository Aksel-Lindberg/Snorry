import Accelerate
import AVFoundation

// MARK: - Pure audio maths helpers (no side effects, fully testable)

enum AudioMath {

    // MARK: RMS → dBFS
    /// Computes root-mean-square of Float32 samples and converts to dBFS.
    /// Returns -160 for silence (zero-energy buffer).
    static func rmsDBFS(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return -160 }
        var rms: Float = 0
        vDSP_measqv(samples, 1, &rms, vDSP_Length(count))
        let rmsSqrt = sqrt(rms)
        guard rmsSqrt > 0 else { return -160 }
        return 20 * log10(rmsSqrt)
    }

    /// Convenience overload for an `AVAudioPCMBuffer` (first channel only).
    static func rmsDBFS(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
        return rmsDBFS(samples: data[0], count: Int(buffer.frameLength))
    }

    // MARK: Exponential moving average
    /// Updates and returns the new EMA value.
    /// α = 1 → full replace; α → 0 → heavy smoothing.
    @inline(__always)
    static func ema(current: Float, new: Float, alpha: Float) -> Float {
        alpha * new + (1 - alpha) * current
    }

    // MARK: Normalise dBFS → 0…1 for waveform display
    /// Maps [-80, 0] dBFS linearly to [0, 1].
    static func normalisedLevel(_ dBFS: Float, floor: Float = -80) -> CGFloat {
        let clamped = max(floor, min(0, dBFS))
        return CGFloat((clamped - floor) / -floor)
    }

    // MARK: Median of a collection
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    // MARK: BRPM from onset intervals

    /// Lower bound for registered breath rate (breaths per minute). Slower patterns are treated as non-snore tempo noise.
    static let minRegisteredBRPM: Double = 10
    /// Upper bound for registered breath rate from interval median.
    static let maxRegisteredBRPM: Double = 60

    /// Inter-onset spacing that maps to `[minRegisteredBRPM, maxRegisteredBRPM]`.
    private static var minIntervalForRegisteredBRPM: Double { 60.0 / maxRegisteredBRPM }
    private static var maxIntervalForRegisteredBRPM: Double { 60.0 / minRegisteredBRPM }

    /// Returns breaths-per-minute from inter-onset intervals (seconds).
    /// Only intervals implying **≥ `minRegisteredBRPM` BRPM** (≤ 6 s at 10 BRPM) and **≤ `maxRegisteredBRPM`** (≥ 1 s) contribute.
    static func brpm(fromIntervals intervals: [Double]) -> Double? {
        let lo = minIntervalForRegisteredBRPM
        let hi = maxIntervalForRegisteredBRPM
        let valid = intervals.filter { $0 >= lo && $0 <= hi }
        guard let med = median(valid), med > 0 else { return nil }
        let raw = 60.0 / med
        guard raw >= minRegisteredBRPM && raw <= maxRegisteredBRPM else { return nil }
        return raw
    }

    // MARK: BRPM ↔ spectral marker (harmonic of breath tempo in audible band)

    /// Fundamental breath-cycle frequency in Hz = BRPM / 60 (sub-audio).
    static func respiratoryRateHz(brpm: Double) -> Double {
        max(1e-6, brpm / 60.0)
    }

    /// Lowest harmonic ≥ `minHz` of the respiratory rhythm — used to mark the spectrum bar
    /// that aligns with detected breath‑rate energy (typically 85–2800 Hz for snores).
    static func brpmHarmonicHighlightHz(brpm: Double, minHz: Double = 85, maxHz: Double = 2800) -> Double? {
        guard brpm >= minRegisteredBRPM, brpm <= 120 else { return nil }
        let f0 = respiratoryRateHz(brpm: brpm)
        let kLow = Swift.max(2, Int(ceil(minHz / f0)))
        for k in kLow ..< 30_000 {
            let f = f0 * Double(k)
            if f > maxHz { return nil }
            if f >= minHz { return f }
        }
        return nil
    }

    /// Band index for a log‑spaced spectrum from `displayMinHz` to Nyquist.
    static func logSpectrumBandIndex(
        freqHz: Double,
        bandCount: Int,
        sampleRate: Double,
        displayMinHz: Double = 45
    ) -> Int {
        guard bandCount > 0 else { return 0 }
        let nyquist = sampleRate / 2
        guard freqHz > 0, freqHz <= nyquist else { return 0 }
        let fClamp = Swift.max(displayMinHz, freqHz)
        let t = (log(fClamp) - log(displayMinHz)) / (log(nyquist) - log(displayMinHz))
        let b = Int(floor(t * Double(bandCount)))
        return min(bandCount - 1, max(0, b))
    }
}
