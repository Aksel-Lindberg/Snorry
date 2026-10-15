import Foundation

// MARK: - Lock-screen RMS gate (relative to night ambient)

/// Pure helpers for the energy-fallback path when SoundAnalysis is off. Matches
/// ambient tracking in ``SnoreEventDetector`` so lock-screen and bout onset logic stay aligned.
enum LockScreenLoudnessGate {

    /// EMA weight when the sample is at or below the current ambient (tracks quiet room).
    static let ambientAlpha: Float = 0.02
    /// Slow upward drift during snoring peaks so the floor does not chase loud bouts.
    static let ambientPeakAlpha: Float = 0.002

    /// Default absolute floor — below typical iPhone snore clips, above silence.
    static let defaultSafetyFloorDB: Float = -60

    /// Seeds from `sample` when `current` is nil; otherwise same EMA rule as the detector baseline.
    static func nextAmbient(current: Float?, sample: Float) -> Float {
        guard let current else { return sample }
        let alpha = sample <= current ? ambientAlpha : ambientPeakAlpha
        return AudioMath.ema(current: current, new: sample, alpha: alpha)
    }

    /// Lock-screen frame counts as loud when it clears the safety floor and rises `riseDB` above ambient.
    static func isLockScreenLoud(
        db: Float,
        ambient: Float,
        riseDB: Float,
        safetyFloorDB: Float = defaultSafetyFloorDB
    ) -> Bool {
        db >= safetyFloorDB && db >= ambient + riseDB
    }
}
