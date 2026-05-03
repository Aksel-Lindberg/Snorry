import Testing
import Foundation
@testable import Snorry

struct SnoreEventDetectorTests {

    // Build a synthetic MonitorTick with a given dBFS value
    private func makeTick(db: Float) -> MonitorTick {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
        buffer.frameLength = 320
        if let data = buffer.floatChannelData?[0] {
            // Fill with constant amplitude proportional to db
            let amp = pow(10, db / 20)
            for i in 0..<320 { data[i] = amp }
        }
        return MonitorTick(dBFS: db, timestamp: Date(), buffer: buffer)
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
}

// Make AVAudioFormat available in test target
import AVFoundation
