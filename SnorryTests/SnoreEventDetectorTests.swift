import Testing
import Foundation
@testable import Snorry

@MainActor
struct SnoreEventDetectorTests {

    // Build a synthetic MonitorTick with a given dBFS value
    private func makeTick(db: Float, at date: Date = Date()) -> MonitorTick {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        if let data = buffer.floatChannelData?[0] {
            // Fill with constant amplitude proportional to db
            let amp = pow(10, db / 20)
            for i in 0..<320 { data[i] = amp }
        }
        return MonitorTick(dBFS: db, timestamp: date, buffer: buffer, nativeBuffer: buffer)
    }

    @Test func noSnoringWithoutClassifier() {
        let detector = SnoreEventDetector()
        detector.start()

        // Feed ticks without activating the classifier
        for _ in 0..<50 {
            detector.feed(classifierResult: false)
            detector.feed(tick: makeTick(db: -30))
        }

        // No events should have been emitted (stream still open)
        detector.stop()
    }

    @Test func brpmComputationWith6Onsets() {
        // Six onsets 2 s apart → BRPM = 60/2 = 30
        var intervals: [Double] = []
        let timestamps = (0..<6).map { Date(timeIntervalSince1970: Double($0) * 2.0) }
        for i in 1..<timestamps.count {
            intervals.append(timestamps[i].timeIntervalSince(timestamps[i - 1]))
        }
        let brpm = AudioMath.brpm(fromIntervals: intervals)
        #expect(brpm != nil && abs(brpm! - 30) < 0.1,
                "6 onsets 2s apart should give 30 BRPM, got \(brpm ?? 0)")
    }

    @Test func confirmedLowBRPMEpisodeDoesNotEndDuringExpectedPause() async {
        let detector = SnoreEventDetector()
        detector.confirmedGapTolerance = 5
        detector.confirmedGapBreathMultiplier = 2.5
        detector.maxConfirmedGapTolerance = 18
        detector.start()

        let stream = detector.stream
        let t0 = Date(timeIntervalSince1970: 1000)

        // Confirm with ~20 BRPM pattern (3 s between onsets).
        for i in 0..<4 {
            let onsetTime = t0.addingTimeInterval(Double(i) * 3.0)
            detector.feed(classifierResult: true)
            detector.feed(tick: makeTick(db: -20, at: onsetTime))
            detector.feed(classifierResult: false)
            detector.feed(tick: makeTick(db: -50, at: onsetTime.addingTimeInterval(0.2)))
        }

        // Quiet period longer than fixed 5 s, shorter than adaptive 7.5 s window.
        detector.feed(classifierResult: false)
        detector.feed(tick: makeTick(db: -50, at: t0.addingTimeInterval(14.0)))

        // Next low-BRPM onset should continue the same confirmed event.
        detector.feed(classifierResult: true)
        detector.feed(tick: makeTick(db: -20, at: t0.addingTimeInterval(15.0)))

        detector.stop()
        var events: [DetectorEvent] = []
        if let stream {
            for await event in stream {
                events.append(event)
            }
        }

        let startedCount = events.reduce(0) { count, event in
            if case .snoreStarted = event { return count + 1 }
            return count
        }
        let endedCount = events.reduce(0) { count, event in
            if case .snoreEnded = event { return count + 1 }
            return count
        }

        #expect(startedCount == 1, "Expected one confirmed event, got \(startedCount)")
        #expect(endedCount == 1, "Expected one final end event on stop(), got \(endedCount)")
    }
}

// Make AVAudioFormat available in test target
import AVFoundation
