import Testing
import Foundation
import AVFoundation
@testable import Snorry

@MainActor
struct SnoreEventDetectorTests {

    private func makeTick(db: Float, at date: Date = Date()) -> MonitorTick {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        if let data = buffer.floatChannelData?[0] {
            let amp = pow(10, db / 20)
            for i in 0..<320 { data[i] = amp }
        }
        return MonitorTick(dBFS: db, timestamp: date, buffer: buffer, nativeBuffer: buffer)
    }

    private func collectEvents(from detector: SnoreEventDetector) async -> [DetectorEvent] {
        detector.stop()
        guard let stream = detector.stream else { return [] }
        var events: [DetectorEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private func startedCount(in events: [DetectorEvent]) -> Int {
        events.reduce(0) { count, event in
            if case .snoreStarted = event { return count + 1 }
            return count
        }
    }

    private func endedCount(in events: [DetectorEvent]) -> Int {
        events.reduce(0) { count, event in
            if case .snoreEnded = event { return count + 1 }
            return count
        }
    }

    /// Feeds classifier-active ticks from `start` through `end` every `step` seconds.
    /// Loud `-20` dBFS ticks land on multiples of `onsetSpacing` for valid BRPM; others stay quiet.
    private func feedActiveWindow(
        detector: SnoreEventDetector,
        from start: Date,
        through end: TimeInterval,
        step: TimeInterval = 0.25,
        onsetSpacing: TimeInterval = 1.5
    ) {
        var elapsed: TimeInterval = 0
        while elapsed <= end {
            let tickTime = start.addingTimeInterval(elapsed)
            let isOnsetTick = isOnsetTime(elapsed, spacing: onsetSpacing)
            let db: Float = isOnsetTick ? -20 : -45
            detector.feed(classifierResult: true)
            detector.feed(tick: makeTick(db: db, at: tickTime))
            elapsed += step
        }
    }

    /// Feeds inactive ticks over a time span.
    private func feedInactiveWindow(
        detector: SnoreEventDetector,
        from start: Date,
        through end: TimeInterval,
        step: TimeInterval = 0.5
    ) {
        var elapsed: TimeInterval = 0
        while elapsed <= end {
            let tickTime = start.addingTimeInterval(elapsed)
            detector.feed(classifierResult: false)
            detector.feed(tick: makeTick(db: -50, at: tickTime))
            elapsed += step
        }
    }

    /// True when `elapsed` is close to a multiple of `spacing` (breath onset tick).
    private func isOnsetTime(_ elapsed: TimeInterval, spacing: TimeInterval) -> Bool {
        guard spacing > 0 else { return false }
        let quotient = elapsed / spacing
        return abs(quotient - quotient.rounded()) < 0.05
    }

    /// Four onsets spaced within an active window (~40 BRPM).
    private func feedFirstEpisodePattern(detector: SnoreEventDetector, t0: Date, onsetSpacing: TimeInterval = 1.5) {
        for index in 0..<4 {
            let t = t0.addingTimeInterval(Double(index) * onsetSpacing)
            detector.feed(classifierResult: true)
            detector.feed(tick: makeTick(db: -20, at: t))
        }
    }

    @Test func noSnoringWithoutClassifier() async {
        let detector = SnoreEventDetector()
        detector.start()

        for _ in 0..<50 {
            detector.feed(classifierResult: false)
            detector.feed(tick: makeTick(db: -30))
        }

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 0)
    }

    @Test func brpmComputationWith6Onsets() {
        let timestamps = (0..<6).map { Date(timeIntervalSince1970: Double($0) * 2.0) }
        let intervals = zip(timestamps, timestamps.dropFirst()).map { $1.timeIntervalSince($0) }
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        #expect(brpm != nil && abs(brpm! - 30) < 0.1)
    }

    @Test func requiresFiveSecondsActiveBeforeStart() async {
        let detector = SnoreEventDetector()
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 2000)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        // 4 s of active time with four onsets — not enough accumulated time.
        feedActiveWindow(detector: detector, from: t0, through: 4.0)

        var events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 0, "Should not confirm before 5 s accumulated active snoring")

        detector.start()
        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 5.5)

        events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1, "Expected confirmation after 5 s accumulated active snoring")
    }

    @Test func classifierOnlyPauseDoesNotCreditGap() async {
        let detector = SnoreEventDetector()
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.activeGapBridge = 4
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 7000)

        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        feedActiveWindow(detector: detector, from: t0, through: 3.0)

        // 2 s classifier-only pause (no inactive ticks) — gap must not count toward 5 s.
        let pauseStart = t0.addingTimeInterval(3.0)
        let pauseEnd = t0.addingTimeInterval(5.0)
        detector.feed(classifierResult: false, at: pauseStart)
        detector.feed(classifierResult: true, at: pauseEnd)

        feedActiveWindow(detector: detector, from: pauseEnd, through: 0.5)

        var events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 0, "Classifier-only pause must not count toward active time")

        detector.start()
        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 3.0)
        detector.feed(classifierResult: false, at: pauseStart)
        detector.feed(classifierResult: true, at: pauseEnd)
        feedActiveWindow(detector: detector, from: pauseEnd, through: 2.5)

        events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1, "Should confirm once true active time reaches 5 s")
    }

    @Test func briefPauseDoesNotCountAsActiveTime() async {
        let detector = SnoreEventDetector()
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.activeGapBridge = 4
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 2500)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        // 3 s active, 2 s inactive, then a sliver of active — must not reach 5 s yet.
        feedActiveWindow(detector: detector, from: t0, through: 3.0)
        feedInactiveWindow(detector: detector, from: t0.addingTimeInterval(3.5), through: 1.5)
        feedActiveWindow(detector: detector, from: t0.addingTimeInterval(5.5), through: 0.5)

        var events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 0, "Pause duration must not count toward the 5 s active total")

        detector.start()
        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 3.0)
        feedInactiveWindow(detector: detector, from: t0.addingTimeInterval(3.5), through: 1.5)
        feedActiveWindow(detector: detector, from: t0.addingTimeInterval(5.5), through: 2.5)

        events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1, "Should confirm once true active time reaches 5 s")
    }

    @Test func longDropoutResetsAccumulatedActiveTime() async {
        let detector = SnoreEventDetector()
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.activeGapBridge = 4
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 3000)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        feedActiveWindow(detector: detector, from: t0, through: 3.0)

        // 5 s inactive — exceeds the 4 s bridge and resets accumulated time.
        feedInactiveWindow(detector: detector, from: t0.addingTimeInterval(3.5), through: 4.5)

        feedActiveWindow(detector: detector, from: t0.addingTimeInterval(8.5), through: 4.0)

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 0, "Long dropout should reset accumulated active time")
    }

    @Test func briefInterSnorePauseStillAccumulates() async {
        let detector = SnoreEventDetector()
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.activeGapBridge = 4
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 3500)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        feedActiveWindow(detector: detector, from: t0, through: 2.0)

        feedInactiveWindow(detector: detector, from: t0.addingTimeInterval(2.5), through: 1.5)

        feedActiveWindow(detector: detector, from: t0.addingTimeInterval(4.5), through: 3.0)

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1, "Brief inter-snore pauses should still reach 5 s accumulated active time")
    }

    @Test func endsEventAfterTenSecondsSilence() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 10
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 4000)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 5.5)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(6.0)))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(14.9)))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(16.0)))

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1)
        #expect(endedCount(in: events) == 1)
    }

    @Test func shortPauseDoesNotEndConfirmedEvent() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 10
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 5000)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 5.5)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(6.0)))

        detector.feed(classifierResult: true)
        detector.feed(tick: makeTick(db: -20, at: t0.addingTimeInterval(13.0)))

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1, "Expected one confirmed event")
        #expect(endedCount(in: events) == 1, "Expected one final end event on stop()")
    }

    @Test func longPauseEndsConfirmedEvent() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 10
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 6000)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 5.5)

        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(6.0)))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(16.0)))

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1)
        #expect(endedCount(in: events) == 1)
    }
}
