import Foundation
import AVFoundation
import os.log

// MARK: - Detector output events

enum DetectorEvent: Sendable {
    /// Classifier state changed (raw, before pattern confirmation).
    case snoringActive(Bool)
    /// Emitted only after ≥4 onsets confirm a valid BRPM pattern.
    /// `at` = first onset timestamp; `captureFrom` = same (used to trim pre-roll).
    case snoreStarted(eventID: UUID, at: Date, captureFrom: Date)
    /// Individual breath peak within a confirmed event.
    case snoreOnset(at: Date)
    /// Emitted when the detector's gap tolerance expires (or on forced reset).
    case snoreEnded(eventID: UUID, at: Date, brpm: Double, peakDB: Float)
    case brpmUpdated(Double)
}

// MARK: - Snore event detector with two-phase confirmation

/// Phase 1 — PENDING: classifier is active but we don't yet have a confirmed pattern.
/// Phase 2 — CONFIRMED: ≥4 onsets with valid BRPM have been detected; event is live.
///
/// Call `resetForNewEpisode()` (from MonitorViewModel when the AlertManager goes idle)
/// to end the current episode and start fresh detection.
final class SnoreEventDetector: @unchecked Sendable {

    // MARK: Tunables
    private let gapTolerance: TimeInterval     = 8.0    // silence that ends a confirmed event
    private let minOnsetInterval: TimeInterval = 0.5    // de-bounce between onsets
    private let onsetThresholdDB: Float        = 12.0   // dB above ambient to register onset
    private let ambientAlpha: Float            = 0.02   // EMA weight for ambient baseline
    private let brpmWindowSize                 = 30     // max onsets used for BRPM

    // MARK: State
    private var pendingID: UUID?            // set when classifier first activates
    private var firstOnsetDate: Date?       // timestamp of very first onset in episode
    private var isConfirmed = false         // true once .snoreStarted has been emitted

    private var currentEventID: UUID?       // same as pendingID after confirmation
    private var eventPeakDB: Float = -160
    private var lastOnsetDate: Date?
    private var silenceStart: Date?
    private var ambientBaseline: Float = -50
    private var lastDB: Float = -160
    private var onsetTimestamps: [Date] = []

    private var classifierActive = false

    private var continuation: AsyncStream<DetectorEvent>.Continuation?
    private(set) var stream: AsyncStream<DetectorEvent>?

    private let logger = Logger(subsystem: "app.Snorry", category: "Detector")

    // MARK: Lifecycle

    func start() {
        let (s, c) = AsyncStream<DetectorEvent>.makeStream()
        stream = s
        continuation = c
        resetState()
    }

    func stop() {
        if isConfirmed { finishCurrentEvent(at: Date()) }
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    /// Called by MonitorViewModel when the AlertManager returns to idle.
    /// Ends the current episode and puts the detector back into idle so
    /// the next snore bout is treated as a brand-new event from scratch.
    func resetForNewEpisode() {
        if isConfirmed {
            finishCurrentEvent(at: Date())
        }
        resetState()
    }

    private func resetState() {
        pendingID        = nil
        firstOnsetDate   = nil
        isConfirmed      = false
        currentEventID   = nil
        eventPeakDB      = -160
        lastOnsetDate    = nil
        silenceStart     = nil
        lastDB           = -160
        onsetTimestamps  = []
        classifierActive = false
        // Preserve ambientBaseline across episodes — it's a continuous measurement.
    }

    // MARK: Classifier feed

    func feed(classifierResult: Bool) {
        classifierActive = classifierResult
        continuation?.yield(.snoringActive(classifierResult))

        if classifierResult && pendingID == nil {
            // First classifier trigger for this episode → enter pending phase.
            pendingID = UUID()
            logger.debug("Snore pending: \(self.pendingID!)")
        }
    }

    // MARK: Audio tick feed

    func feed(tick: MonitorTick) {
        let db  = tick.dBFS
        let now = tick.timestamp
        lastDB  = db

        // Update ambient baseline only while classifier is quiet.
        if !classifierActive {
            ambientBaseline = AudioMath.ema(current: ambientBaseline, new: db, alpha: ambientAlpha)
        }

        // Onset detection: significant dB spike while classifier is active.
        if classifierActive {
            let isOnset = db >= ambientBaseline + onsetThresholdDB
            let gapOK   = lastOnsetDate.map { now.timeIntervalSince($0) >= minOnsetInterval } ?? true
            if isOnset && gapOK {
                registerOnset(at: now)
            }
        }

        // Gap / silence tracking.
        if classifierActive {
            silenceStart = nil
            if db > eventPeakDB { eventPeakDB = db }
        } else if pendingID != nil {
            if silenceStart == nil { silenceStart = now }
            let gap = now.timeIntervalSince(silenceStart!)
            if gap >= gapTolerance {
                if isConfirmed {
                    finishCurrentEvent(at: now)
                } else {
                    logger.debug("Snore pending discarded — no pattern in time")
                    resetState()
                }
            }
        }
    }

    // MARK: Private helpers

    private func registerOnset(at date: Date) {
        if firstOnsetDate == nil { firstOnsetDate = date }
        lastOnsetDate = date

        onsetTimestamps.append(date)
        if onsetTimestamps.count > brpmWindowSize {
            onsetTimestamps.removeFirst()
        }

        if isConfirmed {
            continuation?.yield(.snoreOnset(at: date))
            updateBRPM()
        } else {
            // Try to confirm the episode with the accumulated onsets.
            tryConfirm(at: date)
        }
    }

    /// Transitions from pending → confirmed once a valid BRPM pattern exists (≥4 onsets).
    private func tryConfirm(at now: Date) {
        guard let brpm = computeBRPM(),
              let id = pendingID,
              let captureFrom = firstOnsetDate else { return }

        isConfirmed    = true
        currentEventID = id
        logger.info("Snore event confirmed: \(id), BRPM=\(brpm, format: .fixed(precision: 1))")

        continuation?.yield(.snoreStarted(eventID: id, at: captureFrom, captureFrom: captureFrom))
        continuation?.yield(.brpmUpdated(brpm))
    }

    private func finishCurrentEvent(at date: Date) {
        guard let id = currentEventID else { return }
        let brpm = computeBRPM() ?? 0
        logger.debug("Snore event ended: \(id), BRPM=\(brpm, format: .fixed(precision: 1))")
        continuation?.yield(.snoreEnded(eventID: id, at: date, brpm: brpm, peakDB: eventPeakDB))
        currentEventID = nil
        isConfirmed    = false
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
