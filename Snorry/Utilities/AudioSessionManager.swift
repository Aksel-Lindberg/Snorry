import AVFoundation
import Foundation
import os.log

// MARK: - Central AVAudioSession configuration
/// All AVAudioSession mutations go through this single point.
final class AudioSessionManager: @unchecked Sendable {

    static let shared = AudioSessionManager()
    private let logger = Logger(subsystem: "app.Snorry", category: "AudioSession")

    /// True while `AudioMonitorService` has an active monitoring session (mic tap + engine).
    private let monitoringStateLock = NSLock()
    private var isMonitoringAudioActive = false

    private nonisolated(unsafe) var interruptionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var routeChangeObserver: NSObjectProtocol?
    private nonisolated(unsafe) var mediaResetObserver: NSObjectProtocol?

    private init() {
        installSessionNotifications()
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
        if let mediaResetObserver { NotificationCenter.default.removeObserver(mediaResetObserver) }
    }

    /// Called by `AudioMonitorService` when monitoring starts / stops so route and interruption
    /// handlers only reconfigure while the user expects capture to be running.
    func setMonitoringAudioActive(_ active: Bool) {
        monitoringStateLock.lock()
        isMonitoringAudioActive = active
        monitoringStateLock.unlock()
    }

    private func monitoringAudioActive() -> Bool {
        monitoringStateLock.lock()
        defer { monitoringStateLock.unlock() }
        return isMonitoringAudioActive
    }

    private func installSessionNotifications() {
        let center = NotificationCenter.default
        let main = OperationQueue.main

        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        mediaResetObserver = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: main
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            break
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard options.contains(.shouldResume) else { return }
            guard monitoringAudioActive() else { return }
            AudioMonitorService.shared.resumeAfterInterruptionIfNeeded()
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard monitoringAudioActive() else { return }
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        // Only react to physical device connect/disconnect — categoryChange (3),
        // override (4), and routeConfigurationChange (8) are emitted by our own
        // session updates and would loop if handled here.
        case .oldDeviceUnavailable, .newDeviceAvailable:
            AudioMonitorService.shared.reconfigureAfterRouteChange()
        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        guard monitoringAudioActive() else { return }
        logger.warning("Media services were reset — attempting full session + engine resume")
        AudioMonitorService.shared.resumeAfterInterruptionIfNeeded()
    }

    /// Configure the session for simultaneous recording + playback so the alarm
    /// tone can play while the mic tap remains active.
    ///
    /// Uses `.default` mode so the system applies full speaker EQ and output processing,
    /// matching the level users hear when previewing sounds in Settings.
    /// The 16 kHz mic analysis rate is achieved by `AudioMonitorService`'s internal
    /// `AVAudioConverter` — no need to pin the hardware I/O to 16 kHz, which would
    /// constrain the output path and reduce alarm loudness.
    ///
    /// Uses A2DP (not HFP) so the built-in mic stays active for snore detection and recording.
    /// HFP is only used for settings preview where no microphone capture is needed.
    func configureForMonitoring() throws {
        let session = AVAudioSession.sharedInstance()
        // Clear any HFP replay session left from session-detail clip playback.
        if !monitoringAudioActive() {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothA2DP, .duckOthers]
        )
        try session.setPreferredIOBufferDuration(0.02) // ~20 ms latency
        try session.setActive(true)
        try preferBuiltInMicrophone()
        try applyMonitoringOutputRoute(for: session)
    }

    /// Keeps the monitoring category (A2DP-only) so the built-in mic is not stolen by HFP.
    func prepareOutputRouteForAlarm() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP, .duckOthers]
            )
            try preferBuiltInMicrophone()
            if shouldRouteAlarmToExternalDevice(session) {
                try session.overrideOutputAudioPort(.none)
            } else {
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.allowBluetoothA2DP, .defaultToSpeaker, .duckOthers]
                )
                try preferBuiltInMicrophone()
                try session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            logger.error("Failed to prepare alarm output route: \(error)")
        }
    }

    /// Re-applies monitoring session routing after alarm playback ends.
    func restoreMonitoringAfterAlarm() {
        AudioMonitorService.shared.restoreMonitoringAfterAlarm()
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }
    }

    /// Configure the session for alarm preview and snore clip replay (playback only).
    ///
    /// Uses `.playAndRecord` + `.defaultToSpeaker` so `overrideOutputAudioPort(.speaker)`
    /// is valid (`.playback` rejects that call with OSStatus -50).
    func configureForClipReplay() throws {
        let session = AVAudioSession.sharedInstance()

        if !monitoringAudioActive() {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setActive(true)
        applyPreferredOutputRoute(for: session)
    }

    /// Routes monitoring playback to a connected external device when possible; otherwise loudspeaker.
    private func applyMonitoringOutputRoute(for session: AVAudioSession) throws {
        if shouldRouteAlarmToExternalDevice(session) {
            try session.overrideOutputAudioPort(.none)
        } else {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP, .defaultToSpeaker, .duckOthers]
            )
            try session.overrideOutputAudioPort(.speaker)
        }
    }

    /// Routes clip replay / settings preview to external output when present.
    private func applyPreferredOutputRoute(for session: AVAudioSession = AVAudioSession.sharedInstance()) {
        do {
            if hasExternalOutputRoute(session) {
                try session.overrideOutputAudioPort(.none)
            } else if session.category == .playAndRecord {
                try session.overrideOutputAudioPort(.speaker)
            }
        } catch {
            logger.error("Failed to apply output route: \(error)")
        }
    }

    /// True when a Bluetooth/headphone device is connected for playback.
    /// Pinning the built-in mic can move the active output to Speaker while the
    /// headset remains connected — check `availableInputs` as well as `currentRoute`.
    private func shouldRouteAlarmToExternalDevice(_ session: AVAudioSession) -> Bool {
        if hasExternalOutputRoute(session) { return true }
        return session.availableInputs?.contains(where: { isExternalPlaybackPort($0.portType) }) ?? false
    }

    private func isExternalPlaybackPort(_ portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
             .headphones, .headsetMic, .airPlay, .carAudio, .usbAudio:
            return true
        default:
            return false
        }
    }

    private func hasExternalOutputRoute(_ session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
                 .headphones, .headsetMic, .airPlay, .carAudio, .usbAudio:
                return true
            default:
                return false
            }
        }
    }

    /// Keeps snore detection on the phone mic even when Bluetooth earbuds are connected for output.
    private func preferBuiltInMicrophone() throws {
        let session = AVAudioSession.sharedInstance()
        guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            logger.warning("Built-in microphone not available in route")
            return
        }
        try session.setPreferredInput(builtInMic)
    }

    /// Ends clip replay. Restores monitoring when active; otherwise deactivates the session.
    func resetReplayOverrides() {
        endClipReplaySession(restoreMonitoring: true)
    }

    /// Releases the clip-replay audio session (e.g. when leaving session detail).
    func endClipReplaySession(restoreMonitoring: Bool = true) {
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(.none)
        if restoreMonitoring, monitoringAudioActive() {
            AudioMonitorService.shared.restoreMonitoringAfterAlarm()
        } else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
