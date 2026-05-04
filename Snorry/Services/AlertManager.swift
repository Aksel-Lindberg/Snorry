import Foundation
import os.log

// MARK: - Alert escalation phases
enum AlertPhase: Sendable, Equatable {
    case idle
    case notified                // push notification sent
    case alarming                // sound alarm active (volume stepped externally)
    case cleared                 // snoring stopped, alert dismissed
}

// MARK: - Drives escalation from continuous-snoring duration
/// Update via `update(isSnoring:, at:)` at a regular cadence (~1 Hz is sufficient).
/// Observe `phaseStream` to react to transitions.
final class AlertManager: @unchecked Sendable {

    // MARK: Configuration (mirrored from AlertSettings)
    struct Config: Sendable {
        var notifyDelay: TimeInterval      = 2
        /// Elapsed snoring time before sound alarm starts (seconds).
        var soundAlarmAfter: TimeInterval  = 15
        /// Silence before clearing alert state (seconds).
        var clearDelay: TimeInterval       = 3
        /// Peak alarm volume (0…1); stepped ramp applied in MonitorViewModel.
        var alarmVolume: Float             = 0.85
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
        let (s, c) = AsyncStream<AlertPhase>.makeStream()
        phaseStream = s
        continuation = c
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

    // MARK: Private

    private func advance(elapsed: TimeInterval, at now: Date) {
        switch phase {
        case .idle:
            if elapsed >= config.notifyDelay {
                transition(to: .notified, at: now)
                advance(elapsed: elapsed, at: now)
            }
        case .notified:
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
