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
}
