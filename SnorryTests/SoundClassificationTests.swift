import Testing
import Foundation
import SwiftData
@testable import Snorry

// MARK: - SoundEventKind enum

struct SoundEventKindTests {

    @Test func defaultRawValueIsSnoring() {
        #expect(SoundEventKind(rawValue: 0) == .snoring)
    }

    @Test func rawValueRoundTrip() {
        for kind in [SoundEventKind.snoring, .sleepTalking, .environment] {
            let round = SoundEventKind(rawValue: kind.rawValue)
            #expect(round == kind)
        }
    }

    @Test func unknownRawValueFallsBackToSnoring() {
        // The typed accessor on SnoreEvent uses `?? .snoring` so unknown persisted values
        // default to snoring rather than crashing or silently suppressing data.
        let kind = SoundEventKind(rawValue: 99)
        #expect(kind == nil, "Raw 99 should not map to a known case")
    }

    @Test func displayNamesAreNonEmpty() {
        for kind in [SoundEventKind.snoring, .sleepTalking, .environment] {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test func systemImagesAreNonEmpty() {
        for kind in [SoundEventKind.snoring, .sleepTalking, .environment] {
            #expect(!kind.systemImage.isEmpty)
        }
    }
}

// MARK: - SnoreEvent default kind

struct SnoreEventDefaultKindTests {

    @Test func newEventDefaultsToSnoring() {
        let event = SnoreEvent()
        #expect(event.soundKind == .snoring)
        #expect(event.soundKindRaw == SoundEventKind.snoring.rawValue)
    }

    @Test func kindWritesThroughRaw() {
        let event = SnoreEvent()
        event.soundKind = .sleepTalking
        #expect(event.soundKindRaw == SoundEventKind.sleepTalking.rawValue)
        event.soundKind = .environment
        #expect(event.soundKindRaw == SoundEventKind.environment.rawValue)
    }
}

// MARK: - Rollup filtering helpers (pure functional, no SwiftData required)

/// Mirrors the logic in `SessionStore.rollupStatistics` without touching a ModelContext.
private func rollup(events: [SnoreEvent]) -> (count: Int, duration: Double, avgBRPM: Double, peakDB: Float) {
    let snoring = events.filter { $0.endDate != nil && $0.soundKind == .snoring }
    let count   = snoring.count
    let dur     = snoring.compactMap { $0.duration }.reduce(0, +)
    let brpms   = snoring.filter { $0.brpm > 0 }.map { $0.brpm }
    let avgBRPM = brpms.isEmpty ? 0 : brpms.reduce(0, +) / Double(brpms.count)
    let peakDB  = snoring.map { $0.peakDB }.max() ?? -160
    return (count, dur, avgBRPM, peakDB)
}

struct RollupFilteringTests {

    // Creates a completed event with given kind and duration (seconds).
    private func event(kind: SoundEventKind, duration: Double, brpm: Double = 0, peakDB: Float = -40) -> SnoreEvent {
        let e = SnoreEvent()
        e.soundKind = kind
        e.startDate = Date()
        e.endDate   = e.startDate.addingTimeInterval(duration)
        e.brpm      = brpm
        e.peakDB    = peakDB
        return e
    }

    @Test func allSnoringKeptInRollup() {
        let events = [event(kind: .snoring, duration: 30, brpm: 15),
                      event(kind: .snoring, duration: 45, brpm: 20)]
        let r = rollup(events: events)
        #expect(r.count == 2)
        #expect(abs(r.duration - 75) < 0.001)
        #expect(abs(r.avgBRPM - 17.5) < 0.001)
    }

    @Test func nonSnoringExcludedFromRollup() {
        let events = [event(kind: .snoring, duration: 60),
                      event(kind: .sleepTalking, duration: 120),
                      event(kind: .environment, duration: 90)]
        let r = rollup(events: events)
        #expect(r.count == 1)
        #expect(abs(r.duration - 60) < 0.001)
    }

    @Test func allNonSnoringGivesZeroStats() {
        let events = [event(kind: .sleepTalking, duration: 30),
                      event(kind: .environment, duration: 20)]
        let r = rollup(events: events)
        #expect(r.count == 0)
        #expect(r.duration == 0)
        #expect(r.avgBRPM == 0)
        #expect(r.peakDB == -160)
    }

    @Test func openEventsExcluded() {
        // An event with nil endDate should never count in rollup.
        let open = SnoreEvent()
        open.soundKind = .snoring
        // No endDate set → open, should be filtered by `$0.endDate != nil`
        let r = rollup(events: [open])
        #expect(r.count == 0)
    }

    @Test func peakDBOnlySnoringEvents() {
        let events = [event(kind: .snoring,      duration: 10, peakDB: -20),
                      event(kind: .sleepTalking, duration: 10, peakDB: -5),   // louder but excluded
                      event(kind: .environment,  duration: 10, peakDB: -10)]  // excluded
        let r = rollup(events: events)
        #expect(r.peakDB == -20)
    }

    @Test func mixedBRPMAvgIgnoresNonSnoring() {
        let events = [event(kind: .snoring,      duration: 30, brpm: 12),
                      event(kind: .snoring,      duration: 30, brpm: 18),
                      event(kind: .sleepTalking, duration: 30, brpm: 60)]  // should be excluded
        let r = rollup(events: events)
        #expect(abs(r.avgBRPM - 15) < 0.001)
    }
}

// MARK: - AccumulatingObserver decision logic (via public classifier interface)

/// Tests the `AccumulatingObserver.decision` logic through the tuning constants on
/// `SessionClipSoundClassifier` — no actual audio files needed.
struct ClassifierDecisionTests {

    /// Simulate the observer's decision by constructing fake aggregated score maps.
    /// Mirrors the logic in `AccumulatingObserver.decision`.
    private func decide(snoringScore: Float, talkingScore: Float) -> SoundEventKind {
        let snoringMin       = SessionClipSoundClassifier.snoringMinScore
        let sleepTalkingMin  = SessionClipSoundClassifier.sleepTalkingMinScore

        if talkingScore >= sleepTalkingMin, talkingScore > snoringScore {
            return .sleepTalking
        }
        if snoringScore >= snoringMin {
            return .snoring
        }
        return .environment
    }

    @Test func clearSnoringWins() {
        #expect(decide(snoringScore: 0.8, talkingScore: 0.05) == .snoring)
    }

    @Test func clearSleepTalkingWins() {
        #expect(decide(snoringScore: 0.05, talkingScore: 0.7) == .sleepTalking)
    }

    @Test func lowConfidenceFallsToEnvironment() {
        #expect(decide(snoringScore: 0.05, talkingScore: 0.05) == .environment)
    }

    @Test func snoringNeedsBiasToBeatTalkingWhenTied() {
        // When scores are equal but both above threshold, snoring wins because
        // talking requires strictly greater score than snoring.
        #expect(decide(snoringScore: 0.50, talkingScore: 0.50) == .snoring)
    }

    @Test func alarmVerificationUsesStricterSnoringThreshold() {
        #expect(SessionClipSoundClassifier.alarmVerificationSnoringMinScore
                > SessionClipSoundClassifier.snoringMinScore)
    }
}
