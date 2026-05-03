import Foundation
import os.log

// MARK: - Alert escalation phases
enum AlertPhase: Sendable, Equatable {
    case idle
    case notified                // push notification sent
    case audioLow                // alarm playing at low volume
    case audioMedium             // alarm playing at medium volume
    case audioHigh               // alarm playing at full volume
    case cleared                 // snoring stopped, alert dismissed
}

// MARK: - Drives the escalation state machine from continuous-snoring duration
/// Update via `update(isSnoring:, at:)` at a regular cadence (~1 Hz is sufficient).
/// Observe `phaseStream` to react to transitions.
final class AlertManager: @unchecked Sendable {

    // MARK: Configuration (mirrored from AlertSettings)
    struct Config: Sendable {
        var notifyDelay: TimeInterval      = 30
        var audioLowDelay: TimeInterval    = 60
        var audioMedDelay: TimeInterval    = 90
        var audioHighDelay: TimeInterval   = 120
        var clearDelay: TimeInterval       = 5
        var volumeLow: Float               = 0.20
        var volumeMed: Float               = 0.60
        var volumeHigh: Float              = 1.00
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
            }
        case .notified:
            if elapsed >= config.audioLowDelay {
                transition(to: .audioLow, at: now)
            }
        case .audioLow:
            if elapsed >= config.audioMedDelay {
                transition(to: .audioMedium, at: now)
            }
        case .audioMedium:
            if elapsed >= config.audioHighDelay {
                transition(to: .audioHigh, at: now)
            }
        case .audioHigh, .cleared:
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

    // MARK: Volume for current phase

    var currentVolume: Float {
        switch phase {
        case .audioLow:    return config.volumeLow
        case .audioMedium: return config.volumeMed
        case .audioHigh:   return config.volumeHigh
        default:           return 0
        }
    }

    var isAudioPlaying: Bool {
        switch phase {
        case .audioLow, .audioMedium, .audioHigh: return true
        default: return false
        }
    }
}
