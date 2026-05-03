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
    /// Returns breaths-per-minute given a list of inter-onset intervals (seconds).
    /// Filters physiologically implausible intervals [1.0, 8.0] s (4–60 BRPM).
    static func brpm(fromIntervals intervals: [Double]) -> Double? {
        let valid = intervals.filter { $0 >= 1.0 && $0 <= 8.0 }
        guard let med = median(valid), med > 0 else { return nil }
        return 60.0 / med
    }
}
