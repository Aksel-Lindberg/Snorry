import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {

    // Alert thresholds
    var notifyDelay: Double      = 2
    var audioLowDelay: Double    = 5
    var audioMedDelay: Double    = 10
    var audioHighDelay: Double   = 15
    var clearDelay: Double       = 8
    var volumeLow: Float         = 0.50
    var volumeMed: Float         = 0.80
    var volumeHigh: Float        = 1.00

    /// Snore detection sensitivity level (1–5). 3 = factory default.
    var snoringDetectionSensitivity: Double = 3

    /// Selected alarm tone style.
    var alarmStyle: AlarmStyle = .classic

    private let context: ModelContext
    private var settings: AlertSettings?

    init(context: ModelContext) {
        self.context = context
        load()
    }

    // MARK: Persistence

    private func load() {
        let stored = AlertSettings.load(context: context)
        settings = stored
        notifyDelay                 = stored.notifyDelaySeconds
        audioLowDelay               = stored.audioLowDelaySeconds
        audioMedDelay               = stored.audioMedDelaySeconds
        audioHighDelay              = stored.audioHighDelaySeconds
        clearDelay                  = stored.clearDelaySeconds
        volumeLow                   = stored.volumeLow
        volumeMed                   = stored.volumeMed
        volumeHigh                  = stored.volumeHigh
        snoringDetectionSensitivity = stored.snoringDetectionSensitivity
        alarmStyle                  = AlarmStyle(rawValue: stored.alarmStyleRaw) ?? .classic
    }

    /// Persist current draft values to the SwiftData store.
    func save() {
        guard let stored = settings else { return }
        stored.notifyDelaySeconds              = notifyDelay
        stored.audioLowDelaySeconds            = audioLowDelay
        stored.audioMedDelaySeconds            = audioMedDelay
        stored.audioHighDelaySeconds           = audioHighDelay
        stored.clearDelaySeconds               = clearDelay
        stored.volumeLow                       = volumeLow
        stored.volumeMed                       = volumeMed
        stored.volumeHigh                      = volumeHigh
        stored.snoringDetectionSensitivity     = snoringDetectionSensitivity
        stored.alarmStyleRaw                   = alarmStyle.rawValue
        try? context.save()
    }

    /// Discard unsaved changes by reloading from the SwiftData store.
    func cancel() {
        load()
    }

    /// Reset everything to factory defaults.
    func reset() {
        // Replace with a fresh default object so next load() reads defaults.
        if let old = settings { context.delete(old) }
        let fresh = AlertSettings()
        context.insert(fresh)
        settings = fresh
        load()
    }
}
