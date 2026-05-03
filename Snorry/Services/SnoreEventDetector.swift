import Foundation
import AVFoundation
import os.log

// MARK: - Detector output events

enum DetectorEvent: Sendable {
    case snoreStarted(eventID: UUID, at: Date)
    case snoreOnset(at: Date)               // individual breath peak within an event
    case snoreEnded(eventID: UUID, at: Date, brpm: Double, peakDB: Float)
    case brpmUpdated(Double)
    case snoringActive(Bool)
}

// MARK: - Combines classifier + RMS to detect snore events and compute BRPM

/// Must be driven by two concurrent async tasks feeding `monitorStream` and `classifierStream`.
/// Emits `DetectorEvent` values through its own `AsyncStream`.
final class SnoreEventDetector: @unchecked Sendable {

    // MARK: Tunables
    private let gapTolerance: TimeInterval   = 8.0   // max silence inside one event
    private let minOnsetInterval: TimeInterval = 0.5  // de-bounce between onsets
    private let onsetThresholdDB: Float      = 12.0  // dB above ambient baseline to fire onset
    private let ambientAlpha: Float          = 0.02  // EMA weight for ambient baseline
    private let brpmWindowSize              = 30     // max recent onsets for BRPM

    // MARK: State
    private var isSnoring = false
    private var currentEventID: UUID?
    private var eventStartDate: Date?
    private var eventPeakDB: Float = -160
    private var lastOnsetDate: Date?
    private var silenceStart: Date?

    private var ambientBaseline: Float = -50     // EMA of non-snoring dBFS
    private var lastDB: Float = -160
    private var onsetTimestamps: [Date] = []     // sliding window for BRPM

    private var continuation: AsyncStream<DetectorEvent>.Continuation?
    private(set) var stream: AsyncStream<DetectorEvent>?

    private var classifierActive = false

    private let logger = Logger(subsystem: "app.Snorry", category: "Detector")

    // MARK: Lifecycle

    func start() {
        let (s, c) = AsyncStream<DetectorEvent>.makeStream()
        stream = s
        continuation = c
        reset()
    }

    func stop() {
        if isSnoring { finishCurrentEvent(at: Date()) }
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    private func reset() {
        isSnoring = false
        currentEventID = nil
        eventStartDate = nil
        eventPeakDB = -160
        lastOnsetDate = nil
        silenceStart = nil
        ambientBaseline = -50
        lastDB = -160
        onsetTimestamps = []
        classifierActive = false
    }

    // MARK: Feed from classifier stream
    func feed(classifierResult: Bool) {
        classifierActive = classifierResult
        continuation?.yield(.snoringActive(classifierResult))
    }

    // MARK: Feed from audio tick
    func feed(tick: MonitorTick) {
        let db = tick.dBFS
        let now = tick.timestamp
        lastDB = db

        // Update ambient baseline only while not snoring
        if !classifierActive {
            ambientBaseline = AudioMath.ema(current: ambientBaseline, new: db, alpha: ambientAlpha)
        }

        // Detect peak onset: dB spike ≥ baseline+threshold while classifier says snoring
        if classifierActive {
            let isOnset = db >= ambientBaseline + onsetThresholdDB
            let gapOK = lastOnsetDate.map { now.timeIntervalSince($0) >= minOnsetInterval } ?? true

            if isOnset && gapOK {
                registerOnset(at: now)
            }
        }

        // State machine: start / continue / end event
        if classifierActive {
            silenceStart = nil
            if !isSnoring {
                beginEvent(at: now)
            }
            if db > eventPeakDB { eventPeakDB = db }
        } else if isSnoring {
            // Classifier went quiet — start gap timer
            if silenceStart == nil { silenceStart = now }
            let gap = now.timeIntervalSince(silenceStart!)
            if gap >= gapTolerance {
                finishCurrentEvent(at: now)
            }
        }
    }

    // MARK: Private helpers

    private func beginEvent(at date: Date) {
        let id = UUID()
        currentEventID = id
        eventStartDate = date
        eventPeakDB = lastDB
        isSnoring = true
        silenceStart = nil
        logger.debug("Snore event started \(id)")
        continuation?.yield(.snoreStarted(eventID: id, at: date))
    }

    private func registerOnset(at date: Date) {
        lastOnsetDate = date
        onsetTimestamps.append(date)
        if onsetTimestamps.count > brpmWindowSize {
            onsetTimestamps.removeFirst()
        }
        continuation?.yield(.snoreOnset(at: date))
        updateBRPM()
    }

    private func finishCurrentEvent(at date: Date) {
        guard let id = currentEventID else { return }
        let brpm = computeBRPM()
        isSnoring = false
        currentEventID = nil
        eventStartDate = nil
        silenceStart = nil
        logger.debug("Snore event ended \(id), BRPM=\(brpm ?? 0, format: .fixed(precision: 1))")
        continuation?.yield(.snoreEnded(eventID: id, at: date, brpm: brpm ?? 0, peakDB: eventPeakDB))
        eventPeakDB = -160
    }

    private func updateBRPM() {
        guard let brpm = computeBRPM() else { return }
        continuation?.yield(.brpmUpdated(brpm))
    }

    private func computeBRPM() -> Double? {
        guard onsetTimestamps.count >= 4 else { return nil }
        let intervals = zip(onsetTimestamps, onsetTimestamps.dropFirst())
            .map { $1.timeIntervalSince($0) }
        return AudioMath.brpm(fromIntervals: intervals)
    }
}
