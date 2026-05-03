import Testing
import Foundation
@testable import Snorry

struct AlertManagerTests {

    private func makeManager() -> AlertManager {
        let m = AlertManager()
        // Use production-matching defaults; these are already very short (2/5/10/15 s)
        m.config.notifyDelay      = 2
        m.config.audioLowDelay    = 5
        m.config.audioMedDelay    = 10
        m.config.audioHighDelay   = 15
        m.config.clearDelay       = 1
        m.start()
        return m
    }

    @Test func idleByDefault() {
        let mgr = makeManager()
        #expect(mgr.phase == .idle)
        mgr.stop()
    }

    @Test func transitionsToNotifiedAfterDelay() {
        let mgr = makeManager()
        let start = Date()

        // Drive time to just past notify delay
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(2.5))

        #expect(mgr.phase == .notified)
        mgr.stop()
    }

    @Test func transitionsToAudioLow() {
        let mgr = makeManager()
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))  // past audioLowDelay=5
        #expect(mgr.phase == .audioLow)
        mgr.stop()
    }

    @Test func clearsAfterSilence() {
        let mgr = makeManager()
        let start = Date()
        // Trigger notify phase
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(2.5))
        #expect(mgr.phase == .notified)

        // Now go silent for longer than clearDelay
        let silenceStart = start.addingTimeInterval(3.0)
        mgr.update(isSnoring: false, at: silenceStart)
        mgr.update(isSnoring: false, at: silenceStart.addingTimeInterval(1.5))

        #expect(mgr.phase == .idle, "Should clear after silence")
        mgr.stop()
    }

    @Test func volumeForPhase() {
        let mgr = makeManager()
        mgr.config.volumeLow = 0.2
        mgr.config.volumeMed = 0.6
        mgr.config.volumeHigh = 1.0
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))  // past audioLowDelay=5
        #expect(mgr.phase == .audioLow)
        #expect(abs(mgr.currentVolume - 0.2) < 0.001)
        mgr.stop()
    }
}
