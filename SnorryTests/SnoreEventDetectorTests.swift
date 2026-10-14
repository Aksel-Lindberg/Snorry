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
        guard let stream = detector.stream else { return [] }
        var events: [DetectorEvent] = []
        let collectTask = Task {
            for await event in stream {
                events.append(event)
            }
        }
        detector.stop()
        await collectTask.value
        return events
    }

    private func startedCount(in events: [DetectorEvent]) -> Int {
        events.reduce(0) { count, event in
            if case .snoreStarted = event { return count + 1 }
            return count
        }
    }

    private func snoreStartDates(in events: [DetectorEvent]) -> [Date] {
        events.compactMap { event in
            if case .snoreStarted(_, let at, _) = event { return at }
            return nil
        }
    }

    /// Quiet bed with ~3 dB peaks — matches loudness near real multi-phone recordings.
    private func feedSubtleBreathCycle(
        detector: SnoreEventDetector,
        at start: Date,
        bedDB: Float = -34,
        peakDB: Float = -31,
        step: TimeInterval = 0.25
    ) {
        let dt = step * 0.35
        let t1 = start.addingTimeInterval(dt)
        let t2 = start.addingTimeInterval(dt * 2)
        let t3 = start.addingTimeInterval(dt * 3)
        detector.feed(classifierResult: true, at: start)
        detector.feed(tick: makeTick(db: bedDB, at: start))
        detector.feed(classifierResult: true, at: t1)
        detector.feed(tick: makeTick(db: bedDB + 2, at: t1))
        detector.feed(classifierResult: true, at: t2)
        detector.feed(tick: makeTick(db: bedDB + 4, at: t2))
        detector.feed(classifierResult: true, at: t3)
        detector.feed(tick: makeTick(db: peakDB, at: t3))
    }

    private func feedClassifierActiveBed(
        detector: SnoreEventDetector,
        from start: Date,
        through duration: TimeInterval,
        bedDB: Float,
        step: TimeInterval = 0.25,
        breathAtOnsets: [TimeInterval]
    ) {
        var elapsed: TimeInterval = 0
        while elapsed <= duration {
            let tickTime = start.addingTimeInterval(elapsed)
            if breathAtOnsets.contains(where: { abs($0 - elapsed) < step * 0.6 }) {
                feedSubtleBreathCycle(detector: detector, at: tickTime, bedDB: bedDB)
            } else {
                detector.feed(classifierResult: true, at: tickTime)
                detector.feed(tick: makeTick(db: bedDB, at: tickTime))
            }
            elapsed += step
        }
    }

    private func endedCount(in events: [DetectorEvent]) -> Int {
        events.reduce(0) { count, event in
            if case .snoreEnded = event { return count + 1 }
            return count
        }
    }

    /// Feeds classifier-active ticks from `start` through `end` every `step` seconds.
    /// Each breath cycle at `onsetSpacing` simulates quiet → inhale rise → exhale snore peak.
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
            detector.feed(classifierResult: true, at: tickTime)
            if isOnsetTime(elapsed, spacing: onsetSpacing) {
                feedBreathCycle(detector: detector, at: tickTime, step: step)
            } else {
                detector.feed(tick: makeTick(db: -48, at: tickTime))
            }
            elapsed += step
        }
    }

    /// One breath: quiet trough → rising inhale → loud exhale/snore.
    private func feedBreathCycle(
        detector: SnoreEventDetector,
        at start: Date,
        step: TimeInterval
    ) {
        let dt = step * 0.35
        let t1 = start.addingTimeInterval(dt)
        let t2 = start.addingTimeInterval(dt * 2)
        let t3 = start.addingTimeInterval(dt * 3)
        detector.feed(classifierResult: true, at: start)
        detector.feed(tick: makeTick(db: -48, at: start))
        detector.feed(classifierResult: true, at: t1)
        detector.feed(tick: makeTick(db: -40, at: t1))
        detector.feed(classifierResult: true, at: t2)
        detector.feed(tick: makeTick(db: -32, at: t2))
        detector.feed(classifierResult: true, at: t3)
        detector.feed(tick: makeTick(db: -20, at: t3))
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
            detector.feed(classifierResult: false, at: tickTime)
            detector.feed(tick: makeTick(db: -50, at: tickTime))
            elapsed += step
        }
    }

    /// True when `elapsed` is close to a multiple of `spacing` (breath cycle anchor).
    private func isOnsetTime(_ elapsed: TimeInterval, spacing: TimeInterval) -> Bool {
        guard spacing > 0 else { return false }
        let quotient = elapsed / spacing
        return abs(quotient - quotient.rounded()) < 0.05
    }

    /// Four inhalations spaced within an active window (~40 BRPM).
    private func feedFirstEpisodePattern(detector: SnoreEventDetector, t0: Date, onsetSpacing: TimeInterval = 1.5) {
        for index in 0..<4 {
            let t = t0.addingTimeInterval(Double(index) * onsetSpacing)
            feedBreathCycle(detector: detector, at: t, step: 0.25)
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
        let brpm = AudioMath.brpm(fromTimestamps: timestamps)
        #expect(brpm != nil && abs(brpm! - 30) < 0.1)
    }

    /// Two loud exhale peaks in one breath must not produce two inhalation counts.
    @Test func doubleExhalePeakCountsOneInhalation() async {
        let detector = SnoreEventDetector()
        detector.minContinuousSnoringBeforeConfirm = 3
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 9000)
        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        // Four breath cycles at 2 s spacing → ~30 BRPM; extra exhale peaks must not inflate count.
        for index in 0..<4 {
            let base = t0.addingTimeInterval(Double(index) * 2.0)
            feedBreathCycle(detector: detector, at: base, step: 0.25)
            detector.feed(tick: makeTick(db: -18, at: base.addingTimeInterval(0.45)))
            detector.feed(tick: makeTick(db: -48, at: base.addingTimeInterval(1.3)))
        }

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1)
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

    @Test func strictSilenceGapIgnoresBriefConfirmedBlips() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 10
        detector.strictConfirmedSilenceGap = true
        detector.minContinuousSnoringBeforeConfirm = 3
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 8000)

        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 3.5)

        // 8 s inactive, then a 0.2 s blip — should still end the event (~10 s silence).
        feedInactiveWindow(detector: detector, from: t0.addingTimeInterval(4.0), through: 8.0)
        detector.feed(classifierResult: true, at: t0.addingTimeInterval(12.0))
        detector.feed(tick: makeTick(db: -20, at: t0.addingTimeInterval(12.0)))
        detector.feed(classifierResult: false, at: t0.addingTimeInterval(12.2))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(12.2)))
        feedInactiveWindow(detector: detector, from: t0.addingTimeInterval(12.5), through: 2.0)

        let events = await collectEvents(from: detector)
        #expect(endedCount(in: events) == 1, "10 s silence should end event despite brief blip")
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

    @Test func endsConfirmedEventWhenClassifierStuckWithoutBreathActivity() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 10
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 9000)

        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 5.5)

        // Classifier stays active on flat audio — no further breath cycles.
        let stuckStart = t0.addingTimeInterval(6.0)
        detector.feed(classifierResult: true, at: stuckStart)
        for step in 0..<48 {
            let t = stuckStart + Double(step) * 0.25
            detector.feed(tick: makeTick(db: -30, at: t))
        }

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 1)
        #expect(endedCount(in: events) == 1, "No new breath onsets should end bout even if classifier stays active")
    }

    @Test func confirmedEndTimestampUsesSilenceOnsetNotGapExpiry() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 10
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.onsetThresholdDB = 6
        detector.start()

        let t0 = Date(timeIntervalSince1970: 10_000)

        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))
        feedActiveWindow(detector: detector, from: t0, through: 5.5)

        let silenceOnset = t0.addingTimeInterval(6.0)
        detector.feed(classifierResult: false, at: silenceOnset)
        detector.feed(tick: makeTick(db: -50, at: silenceOnset))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(16.0)))

        let events = await collectEvents(from: detector)
        guard case .snoreEnded(_, let endDate, _, _) = events.last else {
            Issue.record("Expected snoreEnded as final event")
            return
        }
        #expect(abs(endDate.timeIntervalSince(silenceOnset)) < 0.01,
                "Duration should end when silence began, not after the full gap tolerance")
    }

    @Test func learnedFloorConfirmsSameSubtlePatternRegardlessOfClassifierLeadIn() async {
        let t0 = Date(timeIntervalSince1970: 20_000)
        let bed: Float = -34
        let onsetSpacing: TimeInterval = 1.5
        let onsets: [TimeInterval] = [0, onsetSpacing, onsetSpacing * 2, onsetSpacing * 3]

        func runScenario(classifierLeadInQuiet: Bool) async -> [Date] {
            let detector = SnoreEventDetector()
            detector.onsetThresholdDB = 0.75
            detector.minContinuousSnoringBeforeConfirm = 5
            detector.start()

            if classifierLeadInQuiet {
                feedInactiveWindow(
                    detector: detector,
                    from: t0.addingTimeInterval(-2),
                    through: 2.0,
                    step: 0.25
                )
                for tick in stride(from: 0.0, through: 2.0, by: 0.25) {
                    let time = t0.addingTimeInterval(-2 + tick)
                    detector.feed(tick: makeTick(db: bed, at: time))
                }
            }

            feedClassifierActiveBed(
                detector: detector,
                from: t0,
                through: 5.5,
                bedDB: bed,
                breathAtOnsets: onsets
            )
            let events = await collectEvents(from: detector)
            return snoreStartDates(in: events)
        }

        let immediateStarts = await runScenario(classifierLeadInQuiet: false)
        let quietLeadStarts = await runScenario(classifierLeadInQuiet: true)

        #expect(immediateStarts.count == 1)
        #expect(quietLeadStarts.count == 1)
        if immediateStarts.count == 1, quietLeadStarts.count == 1 {
            #expect(abs(immediateStarts[0].timeIntervalSince(quietLeadStarts[0])) <= 0.25)
        }
    }

    @Test func flatQuietBedDoesNotConfirm() async {
        let detector = SnoreEventDetector()
        detector.onsetThresholdDB = 0.75
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.start()

        let t0 = Date(timeIntervalSince1970: 21_000)
        feedClassifierActiveBed(
            detector: detector,
            from: t0,
            through: 6.0,
            bedDB: -55,
            breathAtOnsets: []
        )

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 0)
    }

    @Test func twoBreathCyclesConfirmFirstBoutAndSecondAfterSilenceGap() async {
        let detector = SnoreEventDetector()
        detector.onsetThresholdDB = 6
        detector.minContinuousSnoringBeforeConfirm = 5
        detector.confirmedGapTolerance = 10
        detector.start()

        let t0 = Date(timeIntervalSince1970: 22_000)
        detector.feed(classifierResult: false, at: t0.addingTimeInterval(-1))
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(-1)))

        feedClassifierActiveBed(
            detector: detector,
            from: t0,
            through: 5.5,
            bedDB: -48,
            breathAtOnsets: [0, 1.5]
        )

        let gapStart = t0.addingTimeInterval(6.0)
        feedInactiveWindow(detector: detector, from: gapStart, through: 11.0, step: 0.5)

        let secondBoutStart = gapStart.addingTimeInterval(11.0)
        feedClassifierActiveBed(
            detector: detector,
            from: secondBoutStart,
            through: 5.5,
            bedDB: -48,
            breathAtOnsets: [0, 1.5]
        )

        let events = await collectEvents(from: detector)
        #expect(startedCount(in: events) == 2, "Both bouts should confirm with two breaths and 5 s active")
    }
}
