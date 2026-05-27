import Testing
import Foundation
@testable import Snorry

struct AlertManagerTests {

    private func makeManager() -> AlertManager {
        let m = AlertManager()
        m.config.notifyDelay     = 2
        m.config.soundAlarmAfter = 5
        m.config.clearDelay      = 1
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

        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(2.5))

        #expect(mgr.phase == .notified)
        mgr.stop()
    }

    @Test func transitionsToAlarming() {
        let mgr = makeManager()
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))  // past soundAlarmAfter=5
        #expect(mgr.phase == .alarming)
        mgr.stop()
    }

    @Test func clearsAfterSilence() {
        let mgr = makeManager()
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(2.5))
        #expect(mgr.phase == .notified)

        let silenceStart = start.addingTimeInterval(3.0)
        mgr.update(isSnoring: false, at: silenceStart)
        mgr.update(isSnoring: false, at: silenceStart.addingTimeInterval(1.5))

        #expect(mgr.phase == .idle, "Should clear after silence")
        mgr.stop()
    }

    @Test func volumeCapWhenAlarming() {
        let mgr = makeManager()
        mgr.config.alarmVolume = 0.75
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))
        #expect(mgr.phase == .alarming)
        #expect(abs(mgr.currentVolume - 0.75) < 0.001)
        mgr.stop()
    }

    @Test func pushOnlyStaysNotified() {
        let mgr = makeManager()
        mgr.config.pushEnabled = true
        mgr.config.soundEnabled = false
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(10))
        #expect(mgr.phase == .notified)
        mgr.stop()
    }

    @Test func soundOnlySkipsNotified() {
        let mgr = makeManager()
        mgr.config.pushEnabled = false
        mgr.config.soundEnabled = true
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))
        #expect(mgr.phase == .alarming)
        mgr.stop()
    }

    @Test func alarmingClearsAfterThreeSecondsOfSilence() {
        let mgr = makeManager()
        mgr.config.clearDelay = 3
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))
        #expect(mgr.phase == .alarming)

        let silenceStart = start.addingTimeInterval(6.0)
        mgr.update(isSnoring: false, at: silenceStart)
        mgr.update(isSnoring: false, at: silenceStart.addingTimeInterval(2.9))
        #expect(mgr.phase == .alarming, "Should not clear before 3 s of silence")

        mgr.update(isSnoring: false, at: silenceStart.addingTimeInterval(3.0))
        #expect(mgr.phase == .idle, "Sound alarm should stop after 3 s without snoring")
        mgr.stop()
    }

    @Test func beginEscalationBackdatesElapsedTime() {
        let mgr = makeManager()
        mgr.config.notifyDelay = 3
        let onset = Date()
        mgr.beginEscalation(from: onset.addingTimeInterval(-3.5))
        mgr.update(isSnoring: true, at: onset)
        #expect(mgr.phase == .notified)
        mgr.stop()
    }

    @Test func clearsImmediatelyAfterSnoreBoutEnds() {
        let mgr = makeManager()
        mgr.config.clearDelay = 99  // would block silence-based clear for a long time
        let start = Date()
        mgr.update(isSnoring: true, at: start)
        mgr.update(isSnoring: true, at: start.addingTimeInterval(5.5))
        #expect(mgr.phase == .alarming)
        mgr.clearAfterSnoreBoutEnded()
        #expect(mgr.phase == .idle)
        mgr.stop()
    }
}
