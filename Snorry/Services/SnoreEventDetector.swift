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
    /// Individual inhalation within a confirmed event (start of a breath cycle).
    case snoreOnset(at: Date)
    /// Emitted when the detector's gap tolerance expires (or on forced reset).
    case snoreEnded(eventID: UUID, at: Date, peakDB: Float, avgDB: Float)
}

// MARK: - Snore event detector with two-phase confirmation

/// Phase 1 — PENDING: classifier is active but pattern not yet confirmed.
/// Phase 2 — CONFIRMED: enough onsets confirmed; event is live.
///
/// First episode of a monitoring session requires 5 s continuous rumble-validated snoring
/// and 4 inhalations. Every subsequent episode requires 5 s continuous snoring and
/// 2 inhalations so the alarm re-arms within seconds after a clear.
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
    /// When true, brief classifier blips during a confirmed bout do not reset the silence gap (lock screen).
    var strictConfirmedSilenceGap = false
    /// Minimum uninterrupted rumble-validated snoring before logging begins.
    var minContinuousSnoringBeforeConfirm: TimeInterval = 5.0
    /// Gaps shorter than this between active stretches still count toward the 5 s total (inter-snore pauses).
    var activeGapBridge: TimeInterval = 4.0
    private let minInhalationInterval: TimeInterval = AudioMath.minInhalationInterval
    private let ambientAlpha: Float            = 0.02   // EMA weight for ambient baseline
    private let inhalationWindowSize           = 30     // max inhalations tracked per bout

    /// dB above the ambient baseline required to register the exhale/snore peak of a breath cycle.
    /// Lower values make the detector more sensitive to quieter snores.
    /// Set from ``SnoreDetectionTuning`` using the saved sensitivity level.
    var onsetThresholdDB: Float = 12.0

    // MARK: Breath envelope (inhalation detection)

    private enum BreathPhase {
        case quiet
        case inhaling
        case exhaling
    }

    /// Fast level EMA (~70 ms) — tracks the current inhale ramp.
    private var shortLevelEMA: Float = -50
    /// Slow level EMA (~500 ms) — local trend for trough / rise detection.
    private var longLevelEMA: Float = -50
    private let shortLevelAlpha: Float = 0.28
    private let longLevelAlpha: Float = 0.04
    /// Short-term level must exceed the slow trend by this much to enter the inhaling phase.
    private let inhaleRiseThresholdDB: Float = 2.0
    /// Must settle near or below the slow trend before the next inhale can arm.
    private let quietBelowTrendDB: Float = 1.0
    private var breathPhase: BreathPhase = .quiet

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
    private var lastInhalationDate: Date?
    private var silenceStart: Date?
    private var ambientBaseline: Float = -50
    /// Inhalation timestamps within the current bout — one per breath cycle.
    private var inhalationTimestamps: [Date] = []
    /// Accumulated classifier-active time within the current bout (bridges short inter-snore pauses).
    private var accumulatedActiveTime: TimeInterval = 0
    /// Timestamp of the previous classifier-active tick — not advanced while inactive.
    private var lastActiveTickTimestamp: Date?
    private var classifierInactiveSince: Date?
    /// Anchor for clip pre-roll — set when accumulation last restarted.
    private var accumulationAnchor: Date?
    /// Lock-screen: classifier must stay active this long before resetting the confirmed silence gap.
    private var confirmedActiveStreakStart: Date?
    private let strictConfirmedActiveBridge: TimeInterval = 0.8

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
        lastInhalationDate    = nil
        silenceStart     = nil
        inhalationTimestamps  = []
        shortLevelEMA    = -50
        longLevelEMA     = -50
        breathPhase      = .quiet
        accumulatedActiveTime = 0
        lastActiveTickTimestamp = nil
        classifierInactiveSince = nil
        accumulationAnchor = nil
        confirmedActiveStreakStart = nil
        classifierActive = false
    }

    // MARK: Classifier feed

    func feed(classifierResult: Bool, at timestamp: Date = Date()) {
        feedLock.lock()
        defer { feedLock.unlock() }

        let wasActive = classifierActive
        classifierActive = classifierResult
        continuation?.yield(.snoringActive(classifierResult))

        if wasActive && !classifierResult {
            // Classifier can drop between audio ticks — start the pause clock immediately.
            if classifierInactiveSince == nil {
                classifierInactiveSince = timestamp
            }
        } else if !wasActive && classifierResult {
            resumeFromClassifierPause(at: timestamp)
        }

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

        // Inhalation detection: quiet → rising inhale → loud exhale/snore → quiet.
        if classifierActive {
            updateBreathEnvelope(db: db)
            detectInhalation(db: db, at: now)
            if !isConfirmed {
                tryConfirm(at: now)
            }
        } else {
            breathPhase = .quiet
        }

        // Gap / silence tracking; accumulate level for average.
        if classifierActive {
            if isConfirmed && strictConfirmedSilenceGap {
                if confirmedActiveStreakStart == nil {
                    confirmedActiveStreakStart = now
                }
                if let streakStart = confirmedActiveStreakStart,
                   now.timeIntervalSince(streakStart) >= strictConfirmedActiveBridge {
                    silenceStart = nil
                }
            } else {
                confirmedActiveStreakStart = now
                silenceStart = nil
            }
            if db > eventPeakDB { eventPeakDB = db }
            eventSumDB    += Double(db)
            eventTickCount += 1
        } else {
            confirmedActiveStreakStart = nil
            if pendingID != nil {
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
    }

    // MARK: Private helpers

    private func updateBreathEnvelope(db: Float) {
        shortLevelEMA = AudioMath.ema(current: shortLevelEMA, new: db, alpha: shortLevelAlpha)
        longLevelEMA  = AudioMath.ema(current: longLevelEMA, new: db, alpha: longLevelAlpha)
    }

    /// Tracks quiet → inhale → exhale phases and registers one timestamp per inhalation.
    private func detectInhalation(db: Float, at now: Date) {
        let rising = shortLevelEMA > longLevelEMA + inhaleRiseThresholdDB
        let quiet  = shortLevelEMA <= longLevelEMA + quietBelowTrendDB
        let loud   = db >= ambientBaseline + onsetThresholdDB

        let previousPhase = breathPhase
        switch breathPhase {
        case .quiet:
            if rising { breathPhase = .inhaling }
        case .inhaling:
            if loud { breathPhase = .exhaling }
            else if quiet { breathPhase = .quiet }
        case .exhaling:
            if rising { breathPhase = .inhaling }
            else if !loud && quiet { breathPhase = .quiet }
        }

        // Count one inhalation at the start of each rising phase (after quiet or after exhale).
        if breathPhase == .inhaling && previousPhase != .inhaling {
            registerInhalation(at: now)
        }
    }

    private func registerInhalation(at date: Date) {
        let gapOK = lastInhalationDate.map { date.timeIntervalSince($0) >= minInhalationInterval } ?? true
        guard gapOK else { return }

        if firstOnsetDate == nil { firstOnsetDate = date }
        lastInhalationDate = date

        inhalationTimestamps.append(date)
        if inhalationTimestamps.count > inhalationWindowSize {
            inhalationTimestamps.removeFirst()
        }

        if isConfirmed {
            continuation?.yield(.snoreOnset(at: date))
        } else {
            tryConfirm(at: date)
        }
    }

    /// Transitions from pending → confirmed using `confirmationThreshold` and accumulated active time.
    ///
    /// Requires 5 s of classifier-active snoring (with inter-snore gap bridging) and enough inhalations.
    private func tryConfirm(at now: Date) {
        guard classifierActive,
              inhalationTimestamps.count >= confirmationThreshold,
              let id = pendingID,
              let anchor = accumulationAnchor,
              accumulatedActiveTime >= minContinuousSnoringBeforeConfirm else { return }

        isConfirmed                = true
        currentEventID             = id
        sessionHasConfirmedEpisode = true

        logger.info("Snore event confirmed: \(id), threshold=\(self.confirmationThreshold)")

        continuation?.yield(.snoreStarted(eventID: id, at: anchor, captureFrom: anchor))
    }

    /// Emits `.snoreEnded` and fully resets per-event tracking variables.
    private func finishCurrentEvent(at date: Date) {
        guard let id = currentEventID else { return }
        let avgDB  = eventTickCount > 0 ? Float(eventSumDB / Double(eventTickCount)) : -160
        logger.debug("Snore event ended: \(id), avgDB=\(avgDB, format: .fixed(precision: 1))")
        continuation?.yield(.snoreEnded(eventID: id, at: date, peakDB: eventPeakDB, avgDB: avgDB))

        // Clear all event-specific variables so a fresh pending phase can begin.
        currentEventID  = nil
        pendingID       = nil
        isConfirmed     = false
        firstOnsetDate  = nil
        lastInhalationDate   = nil
        inhalationTimestamps = []
        shortLevelEMA   = -50
        longLevelEMA    = -50
        breathPhase     = .quiet
        eventPeakDB     = -160
        eventSumDB      = 0
        eventTickCount  = 0
        silenceStart    = nil
        confirmedActiveStreakStart = nil
        accumulatedActiveTime = 0
        lastActiveTickTimestamp = nil
        classifierInactiveSince = nil
        accumulationAnchor = nil
    }

    /// Adds elapsed active time only while the classifier is active.
    /// Short inter-snore pauses (< ``activeGapBridge``) preserve accumulated time but are not counted toward it.
    private func updateAccumulatedActiveTime(at now: Date) {
        if classifierActive {
            if classifierInactiveSince != nil {
                resumeFromClassifierPause(at: now)
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

    /// Ends a classifier pause without crediting inactive time toward the 5 s confirmation window.
    private func resumeFromClassifierPause(at now: Date) {
        guard let inactiveSince = classifierInactiveSince else { return }
        let pause = now.timeIntervalSince(inactiveSince)
        if pause >= activeGapBridge {
            accumulatedActiveTime = 0
            accumulationAnchor = now
        }
        classifierInactiveSince = nil
        // Re-anchor so the next active tick does not credit the pause gap.
        lastActiveTickTimestamp = now
    }
}
