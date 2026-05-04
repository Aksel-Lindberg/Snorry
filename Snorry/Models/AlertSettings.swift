import Foundation
import SwiftData

// MARK: - User-configurable alert escalation thresholds
/// One row is always maintained; use AlertSettings.load(context:) to access it.
@Model
final class AlertSettings {

    /// Seconds of continuous snoring before first push notification is sent.
    var notifyDelaySeconds: Double
    /// Seconds after notification before audio alarm begins (low volume).
    var audioLowDelaySeconds: Double
    /// Seconds at low volume before escalating to medium.
    var audioMedDelaySeconds: Double
    /// Seconds at medium volume before escalating to full volume.
    var audioHighDelaySeconds: Double
    /// Seconds of silence before alert is cancelled.
    var clearDelaySeconds: Double

    /// Alarm tone volume levels (0–1).
    var volumeLow: Float
    var volumeMed: Float
    var volumeHigh: Float

    /// Snore detection sensitivity (1 = low, 3 = medium default, 5 = high).
    /// Higher values lower both the onset dB threshold and the classifier confidence
    /// threshold so quieter snores are registered.
    var snoringDetectionSensitivity: Double

    init() {
        notifyDelaySeconds  = 2
        audioLowDelaySeconds  = 5
        audioMedDelaySeconds  = 10
        audioHighDelaySeconds = 15
        clearDelaySeconds   = 5
        volumeLow  = 0.20
        volumeMed  = 0.60
        volumeHigh = 1.00
        snoringDetectionSensitivity = 3
    }

    /// Returns existing or creates default settings.
    @MainActor
    static func load(context: ModelContext) -> AlertSettings {
        let descriptor = FetchDescriptor<AlertSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AlertSettings()
        context.insert(settings)
        return settings
    }
}
