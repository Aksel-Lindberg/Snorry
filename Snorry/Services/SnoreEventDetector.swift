import Foundation
import AVFoundation
import os.log

// MARK: - Detector output events

enum DetectorEvent: Sendable {
    /// Classifier state changed (raw, before pattern confirmation).
    case snoringActive(Bool)
    /// Emitted only after enough onsets confirm a valid pattern.
    /// `at` = first onset timestamp; `captureFrom` = same (used to trim pre-roll).
    case snoreStarted(eventID: UUID, at: Date, captureFrom: Date)
    /// Individual breath peak within a confirmed event.
    case snoreOnset(at: Date)
    /// Emitted when the detector's gap tolerance expires (or on forced reset).
    case snoreEnded(eventID: UUID, at: Date, brpm: Double, peakDB: Float, avgDB: Float)
    case brpmUpdated(Double)
}

// MARK: - Snore event detector with two-phase confirmation

/// Phase 1 — PENDING: classifier is active but pattern not yet confirmed.
/// Phase 2 — CONFIRMED: enough onsets confirmed; event is live.
///
/// First episode of a monitoring session requires 4 onsets + valid BRPM.
/// Every subsequent episode (after at least one `resetForNewEpisode()` call)
/// requires only 2 onsets so the alarm re-arms within seconds after a clear.
///
/// Call `resetForNewEpisode()` when the AlertManager goes idle to end the
/// current episode cleanly and prepare for the next snore bout.
final class SnoreEventDetector: @unchecked Sendable {

    // MARK: Tunables
    private let gapTolerance: TimeInterval     = 8.0    // silence that ends a confirmed event
    private let minOnsetInterval: TimeInterval = 0.5    // de-bounce between onsets
    private let ambientAlpha: Float            = 0.02   // EMA weight for ambient baseline
    private let brpmWindowSize                 = 30     // max onsets used for BRPM

    /// dB above the ambient baseline required to register a breath onset.
    /// Lower values make the detector more sensitive to quieter snores.
    /// Derived from the user-facing sensitivity setting.
    var onsetThresholdDB: Float = 12.0

    // MARK: Session-level flag
    /// True after the first confirmed episode this monitoring session.
    /// Persists through `resetForNewEpisode()` so subsequent episodes confirm faster.
    private var sessionHasConfirmedEpisode = false

    private var confirmationThreshold: Int { sessionHasConfirmedEpisode ? 2 : 4 }

    // MARK: Per-episode state
    private var pendingID: UUID?
    private var firstOnsetDate: Date?
    private var isConfirmed = false

    private var currentEventID: UUID?
    private var eventPeakDB: Float = -160
    /// Accumulates dBFS during classifier-active ticks for computing the event average.
    private var eventSumDB: Double = 0
    private var eventTickCount: Int = 0
    private var lastOnsetDate: Date?
    private var silenceStart: Date?
    private var ambientBaseline: Float = -50
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
        sessionHasConfirmedEpisode = false
        resetEpisodeState()
    }

    func stop() {
        if isConfirmed { finishCurrentEvent(at: Date()) }
        continuation?.finish()
        continuation = nil
        stream = nil
    }

    /// Called by MonitorViewModel when the AlertManager returns to idle.
    /// Ends the current episode (if any) and resets per-episode state so
    /// the next snore bout is detected as a fresh event.
    func resetForNewEpisode() {
        if isConfirmed { finishCurrentEvent(at: Date()) }
        resetEpisodeState()
        // sessionHasConfirmedEpisode intentionally NOT reset here —
        // re-arms faster on the next episode.
    }

    // MARK: Private reset helpers

    /// Resets only per-episode tracking; preserves session-level flags and ambient baseline.
    private func resetEpisodeState() {
        pendingID        = nil
        firstOnsetDate   = nil
        isConfirmed      = false
        currentEventID   = nil
        eventPeakDB      = -160
        eventSumDB       = 0
        eventTickCount   = 0
        lastOnsetDate    = nil
        silenceStart     = nil
        onsetTimestamps  = []
        classifierActive = false
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

        // Gap / silence tracking; accumulate level for average.
        if classifierActive {
            silenceStart = nil
            if db > eventPeakDB { eventPeakDB = db }
            eventSumDB    += Double(db)
            eventTickCount += 1
        } else if pendingID != nil {
            if silenceStart == nil { silenceStart = now }
            let gap = now.timeIntervalSince(silenceStart!)
            if gap >= gapTolerance {
                if isConfirmed {
                    finishCurrentEvent(at: now)
                    resetEpisodeState()
                } else {
                    logger.debug("Snore pending discarded — no pattern before gap")
                    resetEpisodeState()
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
            tryConfirm(at: date)
        }
    }

    /// Transitions from pending → confirmed using `confirmationThreshold`.
    ///
    /// First episode: requires 4 onsets AND a valid BRPM (physiological sanity check).
    /// Subsequent episodes: requires only 2 onsets (pattern already established).
    private func tryConfirm(at now: Date) {
        guard onsetTimestamps.count >= confirmationThreshold,
              let id = pendingID,
              let captureFrom = firstOnsetDate else { return }

        // For first episode, also validate a physiologically plausible breathing rate.
        if !sessionHasConfirmedEpisode {
            guard computeBRPM() != nil else { return }
        }

        isConfirmed                = true
        currentEventID             = id
        sessionHasConfirmedEpisode = true

        let brpm = computeBRPM() ?? 0
        logger.info("Snore event confirmed: \(id), BRPM=\(brpm, format: .fixed(precision: 1)), threshold=\(self.confirmationThreshold)")

        continuation?.yield(.snoreStarted(eventID: id, at: captureFrom, captureFrom: captureFrom))
        if brpm > 0 {
            continuation?.yield(.brpmUpdated(brpm))
        }
    }

    /// Emits `.snoreEnded` and fully resets per-event tracking variables.
    private func finishCurrentEvent(at date: Date) {
        guard let id = currentEventID else { return }
        let brpm   = computeBRPM() ?? 0
        let avgDB  = eventTickCount > 0 ? Float(eventSumDB / Double(eventTickCount)) : -160
        logger.debug("Snore event ended: \(id), BRPM=\(brpm, format: .fixed(precision: 1)), avgDB=\(avgDB, format: .fixed(precision: 1))")
        continuation?.yield(.snoreEnded(eventID: id, at: date, brpm: brpm, peakDB: eventPeakDB, avgDB: avgDB))

        // Clear all event-specific variables so a fresh pending phase can begin.
        currentEventID  = nil
        pendingID       = nil
        isConfirmed     = false
        firstOnsetDate  = nil
        lastOnsetDate   = nil
        onsetTimestamps = []
        eventPeakDB     = -160
        eventSumDB      = 0
        eventTickCount  = 0
        silenceStart    = nil
    }

    private func updateBRPM() {
        guard let brpm = computeBRPM() else { return }
        continuation?.yield(.brpmUpdated(brpm))
    }

    private func computeBRPM() -> Double? {
        // ≥2 breath peaks → ≥1 spacing; ≥3 peaks → smoother median filtering in AudioMath.
        guard onsetTimestamps.count >= 2 else { return nil }
        let intervals = zip(onsetTimestamps, onsetTimestamps.dropFirst())
            .map { $1.timeIntervalSince($0) }
        return AudioMath.brpm(fromIntervals: intervals)
    }
}
