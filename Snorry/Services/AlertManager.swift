import Foundation
import os.log

// MARK: - Alert escalation phases
enum AlertPhase: Sendable, Equatable {
    case idle
    case notified                // push notification(s) — only if push enabled
    case alarming                // sound alarm active (volume stepped externally)
    case cleared                 // snoring stopped, alert dismissed
}

// MARK: - Drives escalation from continuous-snoring duration
/// Update via `update(isSnoring:, at:)` at a regular cadence (~1 Hz is sufficient).
/// Observe `phaseStream` to react to transitions.
///
/// **Channels:** If only push is enabled, escalates to `.notified` and stays there.
/// If only sound is enabled, goes from idle → `.alarming` after `soundAlarmAfter`.
/// If both are enabled: idle → `.notified` after `notifyDelay` → `.alarming` after `soundAlarmAfter`.
final class AlertManager: @unchecked Sendable {

    // MARK: Configuration (mirrored from AlertSettings)
    struct Config: Sendable {
        var notifyDelay: TimeInterval      = 2
        var soundAlarmAfter: TimeInterval  = 15
        var clearDelay: TimeInterval       = 3
        var alarmVolume: Float             = 0.85
        var pushEnabled: Bool              = true
        var soundEnabled: Bool             = true
    }

    var config = Config()

    private(set) var phase: AlertPhase = .idle {
        didSet { if phase != oldValue { continuation?.yield(phase) } }
    }

    private var snoringStartDate: Date?
    private var silenceStartDate: Date?

    private var continuation: AsyncStream<AlertPhase>.Continuation?
    private(set) var phaseStream: AsyncStream<AlertPhase>?

    private let logger = Logger(subsystem: "app.Snorry", category: "AlertManager")

    // MARK: Lifecycle

    func start() {
        let (stream, continuation) = AsyncStream<AlertPhase>.makeStream()
        phaseStream = stream
        self.continuation = continuation
        phase = .idle
        snoringStartDate = nil
        silenceStartDate = nil
    }

    func stop() {
        phase = .idle
        snoringStartDate = nil
        silenceStartDate = nil
        continuation?.finish()
        continuation = nil
        phaseStream = nil
    }

    // MARK: Drive the state machine

    func update(isSnoring: Bool, at now: Date = Date()) {
        if isSnoring {
            silenceStartDate = nil

            if snoringStartDate == nil {
                snoringStartDate = now
            }
            let elapsed = now.timeIntervalSince(snoringStartDate!)
            advance(elapsed: elapsed, at: now)
        } else {
            if phase != .idle {
                if silenceStartDate == nil { silenceStartDate = now }
                let silenceDuration = now.timeIntervalSince(silenceStartDate!)
                if silenceDuration >= config.clearDelay {
                    clear()
                }
            }
        }
    }

    /// Call when `SnoreEventDetector` emits `.snoreEnded` — stops alarm/pushes immediately instead of waiting for `clearDelay`.
    func clearAfterSnoreBoutEnded() {
        guard phase != .idle else { return }
        clear()
    }

    // MARK: Private

    private func advance(elapsed: TimeInterval, at now: Date) {
        let push = config.pushEnabled
        let sound = config.soundEnabled

        switch phase {
        case .idle:
            // Neither channel — remain idle.
            guard push || sound else { return }

            // Sound only: go straight to alarming after soundAlarmAfter.
            if !push, sound {
                if elapsed >= config.soundAlarmAfter {
                    transition(to: .alarming, at: now)
                }
                return
            }

            // Push (alone or with sound): enter notified after notifyDelay.
            if push, elapsed >= config.notifyDelay {
                transition(to: .notified, at: now)
                advance(elapsed: elapsed, at: now)
            }

        case .notified:
            // Push only: stay in notified until silence clears.
            guard sound else { return }
            if elapsed >= config.soundAlarmAfter {
                transition(to: .alarming, at: now)
            }

        case .alarming, .cleared:
            break
        }
    }

    private func transition(to newPhase: AlertPhase, at now: Date) {
        logger.info("Alert transition: \(String(describing: self.phase)) → \(String(describing: newPhase))")
        phase = newPhase
    }

    private func clear() {
        logger.info("Alert cleared")
        snoringStartDate = nil
        silenceStartDate = nil
        phase = .idle
    }

    // MARK: Volume cap (ramp uses fractions of this in MonitorViewModel)

    var currentVolume: Float {
        switch phase {
        case .alarming: return config.alarmVolume
        default:        return 0
        }
    }

    var isAudioPlaying: Bool {
        phase == .alarming
    }
}
