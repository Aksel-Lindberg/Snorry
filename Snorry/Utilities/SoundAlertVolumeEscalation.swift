import Foundation

// MARK: - Progressive volume tiers for live sound alerts

enum SoundAlertVolumeEscalation {

    /// Volume fraction for a 1-based burst index (synthesized tone styles).
    static func volumeFraction(burstIndex: Int) -> Float {
        guard burstIndex >= 1 else { return SoundAlertVolumeDefaults.tierFractions[0] }
        let tierIndex = min(
            (burstIndex - 1) / SoundAlertVolumeDefaults.burstsPerTier,
            SoundAlertVolumeDefaults.tierFractions.count - 1
        )
        return SoundAlertVolumeDefaults.tierFractions[tierIndex]
    }

    /// Volume fraction for elapsed continuous-play seconds (recorded clip styles).
    static func volumeFraction(elapsed: TimeInterval) -> Float {
        let tierIndex = min(
            max(0, Int(elapsed / SoundAlertVolumeDefaults.secondsPerTier)),
            SoundAlertVolumeDefaults.tierFractions.count - 1
        )
        return SoundAlertVolumeDefaults.tierFractions[tierIndex]
    }

    /// Applies tier fraction to the master alarm volume with the standard output clamp.
    static func effectiveVolume(baseVolume: Float, fraction: Float) -> Float {
        max(
            SoundAlertVolumeDefaults.minimumOutputVolume,
            min(1.0, baseVolume * fraction)
        )
    }

    /// Rounds a tier fraction to an integer percent for UI display.
    static func displayPercent(forFraction fraction: Float) -> Int {
        Int((fraction * 100).rounded())
    }
}
