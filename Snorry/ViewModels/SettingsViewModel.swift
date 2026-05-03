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
    var clearDelay: Double       = 5
    var volumeLow: Float         = 0.20
    var volumeMed: Float         = 0.60
    var volumeHigh: Float        = 1.00

    private let context: ModelContext
    private var settings: AlertSettings?

    init(context: ModelContext) {
        self.context = context
        load()
    }

    private func load() {
        let s = AlertSettings.load(context: context)
        settings = s
        notifyDelay    = s.notifyDelaySeconds
        audioLowDelay  = s.audioLowDelaySeconds
        audioMedDelay  = s.audioMedDelaySeconds
        audioHighDelay = s.audioHighDelaySeconds
        clearDelay     = s.clearDelaySeconds
        volumeLow      = s.volumeLow
        volumeMed      = s.volumeMed
        volumeHigh     = s.volumeHigh
    }

    func save() {
        guard let s = settings else { return }
        s.notifyDelaySeconds    = notifyDelay
        s.audioLowDelaySeconds  = audioLowDelay
        s.audioMedDelaySeconds  = audioMedDelay
        s.audioHighDelaySeconds = audioHighDelay
        s.clearDelaySeconds     = clearDelay
        s.volumeLow             = volumeLow
        s.volumeMed             = volumeMed
        s.volumeHigh            = volumeHigh
        try? context.save()
    }

    func reset() {
        settings = AlertSettings()
        if let s = settings { context.insert(s) }
        load()
    }
}
