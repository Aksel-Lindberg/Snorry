import Foundation
import AVFoundation
import os.log

// MARK: - Detector output events

enum DetectorEvent: Sendable {
    /// Classifier state changed (raw, before pattern confirmation).
    case snoringActive(Bool)
    /// Emitted only after enough onsets confirm a valid pattern.
    /// `at` = start of uninterrupted rumble-validated snoring; `captureFrom` = same (used to trim pre-roll).
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
/// First episode of a monitoring session requires 5 s continuous rumble-validated snoring,
/// 4 onsets, and valid BRPM. Every subsequent episode requires 5 s continuous snoring and
/// 2 onsets so the alarm re-arms within seconds after a clear.
///
/// Confirmed events end after 10 s of classifier silence.
///
/// Call `resetForNewEpisode()` when the AlertManager goes idle to end the
/// current episode cleanly and prepare for the next snore bout.
final class SnoreEventDetector: @unchecked Sendable {

    // MARK: Tunables
    /// Seconds of silence before a still-pending (unconfirmed) episode is discarded.
    /// Set by MonitorViewModel at session start.
    var gapTolerance: TimeInterval             = 3.0
    /// Seconds of silence before a **confirmed** snore event ends and is stored.
    var confirmedGapTolerance: TimeInterval    = 10.0
    /// Minimum uninterrupted rumble-validated snoring before logging begins.
    var minContinuousSnoringBeforeConfirm: TimeInterval = 5.0
    /// Gaps shorter than this between active stretches still count toward the 5 s total (inter-snore pauses).
    var activeGapBridge: TimeInterval = 4.0
    private let minOnsetInterval: TimeInterval = 0.5    // de-bounce between onsets
    private let ambientAlpha: Float            = 0.02   // EMA weight for ambient baseline
    private let brpmWindowSize                 = 30     // max onsets used for BRPM

    /// dB above the ambient baseline required to register a breath onset.
    /// Lower values make the detector more sensitive to quieter snores.
    /// Set from ``SnoreDetectionTuning`` using the saved sensitivity level.
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
    /// Accumulated classifier-active time within the current bout (bridges short inter-snore pauses).
    private var accumulatedActiveTime: TimeInterval = 0
    /// Timestamp of the previous classifier-active tick — not advanced while inactive.
    private var lastActiveTickTimestamp: Date?
    private var classifierInactiveSince: Date?
    /// Anchor for clip pre-roll — set when accumulation last restarted.
    private var accumulationAnchor: Date?

    private var classifierActive = false

    private var continuation: AsyncStream<DetectorEvent>.Continuation?
    private(set) var stream: AsyncStream<DetectorEvent>?

    private let logger = Logger(subsystem: "app.Snorry", category: "Detector")

    /// Audio ticks (`feed(tick:)`) and classifier frames (`feed(classifierResult:)`) run on different
    /// concurrent tasks — serialize mutations so detector state stays coherent when the phone locks.
    private let feedLock = NSLock()

    // MARK: Lifecycle

    func start() {
        let (s, c) = AsyncStream<DetectorEvent>.makeStream()
        stream = s
        continuation = c
        sessionHasConfirmedEpisode = false
        resetEpisodeState()
    }

    func stop() {
        feedLock.lock()
        if isConfirmed { finishCurrentEvent(at: Date()) }
        feedLock.unlock()

        continuation?.finish()
        continuation = nil
        stream = nil
    }

    /// Called by MonitorViewModel when the AlertManager returns to idle.
    /// Ends the current episode (if any) and resets per-episode state so
    /// the next snore bout is detected as a fresh event.
    func resetForNewEpisode() {
        feedLock.lock()
        defer { feedLock.unlock() }
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
        accumulatedActiveTime = 0
        lastActiveTickTimestamp = nil
        classifierInactiveSince = nil
        accumulationAnchor = nil
        classifierActive = false
    }

    // MARK: Classifier feed

    func feed(classifierResult: Bool) {
        feedLock.lock()
        defer { feedLock.unlock() }

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
        feedLock.lock()
        defer { feedLock.unlock() }

        let db  = tick.dBFS
        let now = tick.timestamp

        updateAccumulatedActiveTime(at: now)

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
            if !isConfirmed {
                tryConfirm(at: now)
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
            // Use a longer gap tolerance once confirmed to bridge between individual snores
            // (hysteresis: harder to leave the snoring state than to enter it).
            let effectiveGap = isConfirmed ? confirmedGapTolerance : gapTolerance
            if gap >= effectiveGap {
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

    /// Transitions from pending → confirmed using `confirmationThreshold` and accumulated active time.
    ///
    /// Requires 5 s of classifier-active snoring (with inter-snore gap bridging), existing onset count,
    /// and (first bout) valid BRPM.
    private func tryConfirm(at now: Date) {
        guard classifierActive,
              onsetTimestamps.count >= confirmationThreshold,
              let id = pendingID,
              let anchor = accumulationAnchor,
              accumulatedActiveTime >= minContinuousSnoringBeforeConfirm else { return }

        // For first episode, also validate a physiologically plausible breathing rate.
        if !sessionHasConfirmedEpisode {
            guard computeBRPM() != nil else { return }
        }

        isConfirmed                = true
        currentEventID             = id
        sessionHasConfirmedEpisode = true

        let brpm = computeBRPM() ?? 0
        logger.info("Snore event confirmed: \(id), BRPM=\(brpm, format: .fixed(precision: 1)), threshold=\(self.confirmationThreshold)")

        continuation?.yield(.snoreStarted(eventID: id, at: anchor, captureFrom: anchor))
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
        accumulatedActiveTime = 0
        lastActiveTickTimestamp = nil
        classifierInactiveSince = nil
        accumulationAnchor = nil
    }

    /// Adds elapsed active time only while the classifier is active.
    /// Short inter-snore pauses (< ``activeGapBridge``) preserve accumulated time but are not counted toward it.
    private func updateAccumulatedActiveTime(at now: Date) {
        if classifierActive {
            if let inactiveSince = classifierInactiveSince {
                let pause = now.timeIntervalSince(inactiveSince)
                if pause >= activeGapBridge {
                    accumulatedActiveTime = 0
                    accumulationAnchor = now
                }
                classifierInactiveSince = nil
                // Resuming after a pause — do not credit inactive elapsed time toward the 5 s total.
                lastActiveTickTimestamp = now
            } else if let lastActive = lastActiveTickTimestamp {
                accumulatedActiveTime += now.timeIntervalSince(lastActive)
                lastActiveTickTimestamp = now
            } else {
                lastActiveTickTimestamp = now
            }
            if accumulationAnchor == nil { accumulationAnchor = now }
        } else if classifierInactiveSince == nil {
            classifierInactiveSince = now
        }
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
