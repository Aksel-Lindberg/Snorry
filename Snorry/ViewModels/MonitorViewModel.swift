import Foundation
import AVFoundation
import SwiftData
import UIKit

// MARK: - Live monitoring state (fed to MonitorView + HomeView)
@Observable
@MainActor
final class MonitorViewModel {

    // MARK: Published state
    var isMonitoring = false
    /// Raw classifier state — true as soon as the model detects a snoring-like sound.
    var isSnoring = false
    /// True only once a valid BRPM pattern (≥4 onsets) has been confirmed.
    /// AlertManager is fed this flag so a single snore-like sound never triggers alerts.
    var isEpisodeConfirmed = false
    var currentDB: Float = -160
    var currentBRPM: Double = 0
    var brpmAvailable = false
    var alertPhase: AlertPhase = .idle
    var elapsedSeconds: Int = 0
    var snoreEventCount = 0
    var recentSession: SnoreSession?

    /// Three-state detection status for the UI status badge.
    enum DetectionPhase { case quiet, detecting, confirmed }
    var detectionPhase: DetectionPhase {
        if isEpisodeConfirmed { return .confirmed }
        if isSnoring           { return .detecting }
        return .quiet
    }

    /// Lowest harmonic of the respiratory tempo that falls in the snore-heavy band (~85–2800 Hz).
    var spectrumBRPMHighlightHz: Double? {
        guard isEpisodeConfirmed, brpmAvailable, currentBRPM > 0 else { return nil }
        return AudioMath.brpmHarmonicHighlightHz(brpm: currentBRPM)
    }

    /// Matching bar for the live log spectrum (aligned with `spectrumBandCount`).
    var spectrumBRPMHighlightBandIndex: Int? {
        guard let hz = spectrumBRPMHighlightHz else { return nil }
        return AudioMath.logSpectrumBandIndex(
            freqHz: hz,
            bandCount: spectrumBandCount,
            sampleRate: AudioMonitorService.targetSampleRate
        )
    }

    /// Normalised FFT power per logarithmic frequency band (0…1), low Hz on the left.
    var spectrumBands: [Float] = []

    /// Live timeline (one point per second)
    var timelinePoints: [TimelinePoint] = []

    struct TimelinePoint: Identifiable {
        let id = UUID()
        let time: Date
        let dBFS: Float
        let brpm: Double
        let isSnoring: Bool
    }

    // MARK: Permissions
    enum MicPermission: Equatable { case undetermined, granted, denied }
    var microphonePermission: MicPermission = .undetermined
    var notificationAuthorized = false

    // MARK: Private services
    private let audioService = AudioMonitorService.shared
    private let classifier   = SnoreClassifier()
    private let detector     = SnoreEventDetector()
    private let alertManager = AlertManager()
    private let alarmPlayer  = AlarmTonePlayer()
    private let clipRecorder = ClipRecorder()
    private let notifications = NotificationManager.shared
    /// FFT bands — must stay in sync with `spectrumAnalyzer`.
    private let spectrumBandCount = 52

    /// Hann-windowed FFT → log-spaced spectrum for snore detail.
    private let spectrumAnalyzer: LiveSpectrumAnalyzer

    private var sessionStore: SessionStore?
    private var activeSession: SnoreSession?
    private var activeEventID: UUID?

    // Tracks an open AAC file for exactly one detector `SnoreEvent` (opened on `.snoreStarted`, closed on `.snoreEnded`).
    private var clipOpen = false
    /// True between detector `snoreStarted` and `snoreEnded` — keeps the sound alarm on during classifier-quiet gaps between breaths.
    private var activeSnoreEpisode = false

    private var monitorTask: Task<Void, Never>?
    private var classifierTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var elapsedTimer: Task<Void, Never>?
    private var timelineTimer: Task<Void, Never>?
    /// Steps alarm volume every 2 s while `.alarming`; cancelled when snoring stops.
    private var alarmRampTask: Task<Void, Never>?
    /// Fires repeated push notifications while in `.notified`.
    private var pushRepeatTask: Task<Void, Never>?

    /// Copied from settings at session start (alert UI / playback).
    private var sessionPushEnabled = true
    private var sessionSoundEnabled = true
    private var sessionPushRepeatEnabled = false
    private var sessionPushRepeatInterval: TimeInterval = 60

    private let modelContext: ModelContext

    /// Seconds between alarm volume steps (20% of max per step until cap).
    private static let alarmVolumeStepInterval: TimeInterval = 2

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.spectrumAnalyzer = LiveSpectrumAnalyzer(bandCount: spectrumBandCount)
        sessionStore = SessionStore(context: modelContext)
        checkPermissions()
    }

    // MARK: Permission checks

    func checkPermissions() {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:      microphonePermission = .granted
        case .denied:       microphonePermission = .denied
        default:            microphonePermission = .undetermined
        }
    }

    func requestMicrophonePermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphonePermission = granted ? .granted : .denied
    }

    func requestNotifications() async {
        await notifications.requestAuthorization()
        notificationAuthorized = notifications.isAuthorized
    }

    // MARK: Start / Stop

    func startMonitoring() {
        guard !isMonitoring,
              microphonePermission == .granted,
              let store = sessionStore else { return }

        UIApplication.shared.isIdleTimerDisabled = true

        isMonitoring = true
        isSnoring = false
        activeSnoreEpisode = false
        elapsedSeconds = 0
        snoreEventCount = 0
        spectrumBands = []
        timelinePoints = []
        alertPhase = .idle

        let session = store.startSession()
        activeSession = session

        do {
            classifier.start()
            detector.start()
            alertManager.start()
            try audioService.start()
        } catch {
            isMonitoring = false
            return
        }

        // Apply saved alert settings
        let settings = AlertSettings.load(context: modelContext)
        sessionPushEnabled          = settings.pushNotificationEnabled
        sessionSoundEnabled         = settings.soundAlarmEnabled
        sessionPushRepeatEnabled    = settings.pushRepeatEnabled
        sessionPushRepeatInterval   = settings.pushRepeatIntervalSeconds

        alertManager.config.notifyDelay       = settings.notifyDelaySeconds
        alertManager.config.soundAlarmAfter   = settings.soundAlarmAfterSeconds
        // Same window as snore-event end: alarm stops only after this much quiet (not after brief between-breath gaps).
        alertManager.config.clearDelay        = settings.clearDelaySeconds
        alertManager.config.alarmVolume       = settings.alarmVolume
        alertManager.config.pushEnabled       = settings.pushNotificationEnabled
        alertManager.config.soundEnabled      = settings.soundAlarmEnabled

        // User slider: silence duration before ending/storing a snore bout (detector gap).
        detector.gapTolerance = settings.clearDelaySeconds

        // Alarm tone style for this session.
        alarmPlayer.setStyle(AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic)

        // Map sensitivity (1–5) to detection thresholds using a power curve so that
        // levels 4–5 produce noticeably larger jumps in sensitivity than levels 1–2.
        // blend=0 (low) → high thresholds; blend=1 (very high) → low thresholds.
        let blend = pow(Float((settings.snoringDetectionSensitivity - 1) / 4), 1.5)
        detector.onsetThresholdDB        = (1 - blend) * 20.0 + blend * 2.0    // 20 dB → 2 dB
        classifier.confidenceThreshold   = (1 - blend) * 0.75 + blend * 0.30   // 0.75 → 0.30

        startTasks()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        // Close any per-event AAC file and close the SwiftData row if monitoring stops mid-snore.
        finalizeOpenClipAndEventIfInterrupted()

        cancelTasks()
        audioService.stop()
        classifier.stop()
        detector.stop()
        alertManager.stop()
        alarmPlayer.stop()
        notifications.cancelSnoringAlert()

        sessionStore?.finalizeSession()
        recentSession = activeSession
        activeSession = nil
        activeEventID = nil

        isMonitoring       = false
        isSnoring          = false
        activeSnoreEpisode = false
        isEpisodeConfirmed = false
        alertPhase         = .idle
        currentBRPM        = 0
        brpmAvailable      = false

        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Async pipelines

    private func startTasks() {
        // 1. Consume AudioMonitorService ticks → classifier + detector + clip recorder
        monitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let stream = audioService.stream else { return }
            for await tick in stream {
                guard !Task.isCancelled else { break }
                let time = AVAudioTime(sampleTime: 0,
                                      atRate: AudioMonitorService.targetSampleRate)
                classifier.analyze(buffer: tick.buffer, at: time)
                detector.feed(tick: tick)

                // Write native-format PCM to the clip for whichever snore-event file is currently open.
                // Using the native buffer (not the 16 kHz analysis buffer) preserves the full
                // frequency range so replay sounds exactly like the original recording.
                if clipOpen {
                    clipRecorder.write(buffer: tick.nativeBuffer)
                }

                // Update live dB + waveform on main actor
                // Live power spectrum — same PCM as recording / classifier (~20 ms frame).
                let rawBands = spectrumAnalyzer.bands(fromPCM: tick.buffer)
                if spectrumBands.count != rawBands.count {
                    spectrumBands = rawBands
                } else {
                    let a: Float = 0.38
                    for i in rawBands.indices {
                        spectrumBands[i] = a * rawBands[i] + (1 - a) * spectrumBands[i]
                    }
                }

                currentDB = tick.dBFS
                if tick.dBFS > (activeSession?.peakDB ?? -160) {
                    activeSession?.peakDB = tick.dBFS
                }
            }
        }

        // 2. Classifier result → detector
        classifierTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = classifier.stream else { return }
            for await result in stream {
                guard !Task.isCancelled else { break }
                detector.feed(classifierResult: result)
            }
        }

        // 3. Detector events → clip recorder + store + alert (@MainActor: SessionStore is main-thread only)
        detectorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let stream = detector.stream else { return }
            for await event in stream {
                guard !Task.isCancelled else { break }
                handle(detectorEvent: event)
            }
        }

        // 4. Alert manager phase changes → notification + alarm
        alertTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let stream = alertManager.phaseStream else { return }
            for await phase in stream {
                guard !Task.isCancelled else { break }
                alertPhase = phase
                handleAlertPhase(phase)
            }
        }

        // 5. Elapsed timer (1 Hz)
        elapsedTimer = Task { @MainActor [weak self] in
            while true {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(1))
                guard let self, isMonitoring else { break }
                elapsedSeconds += 1
                // Episode flag keeps alerts active between breaths (classifier often goes quiet briefly).
                let sustainedSnoring = isEpisodeConfirmed && (isSnoring || activeSnoreEpisode)
                alertManager.update(isSnoring: sustainedSnoring)
                // Persist waveform sample every second
                sessionStore?.addWaveformSample(
                    dBFS: currentDB,
                    brpm: currentBRPM,
                    isSnoringActive: isSnoring
                )
                timelinePoints.append(TimelinePoint(
                    time: Date(),
                    dBFS: currentDB,
                    brpm: currentBRPM,
                    isSnoring: isSnoring
                ))
                // Keep at most 8 hours of data in memory
                if timelinePoints.count > 28_800 { timelinePoints.removeFirst() }
            }
        }
    }

    private func cancelTasks() {
        monitorTask?.cancel();   monitorTask = nil
        classifierTask?.cancel(); classifierTask = nil
        detectorTask?.cancel();  detectorTask = nil
        alertTask?.cancel();     alertTask = nil
        elapsedTimer?.cancel();  elapsedTimer = nil
        timelineTimer?.cancel(); timelineTimer = nil
        alarmRampTask?.cancel(); alarmRampTask = nil
        pushRepeatTask?.cancel(); pushRepeatTask = nil
    }

    // MARK: Event handling

    private func handle(detectorEvent event: DetectorEvent) {
        switch event {
        case .snoringActive(let active):
            isSnoring = active

        case .snoreStarted(let id, let at, let captureFrom):
            activeEventID      = id
            snoreEventCount   += 1
            isEpisodeConfirmed = true
            activeSnoreEpisode = true
            // Fresh BRPM estimation for each new detector bout / event.
            currentBRPM       = 0
            brpmAvailable     = false
            sessionStore?.beginEvent(id: id, at: at)

            // One AAC file per SwiftData SnoreEvent: pre-roll → end of detector bout (silence gap).
            // Use the native hardware format so the clip replays at the original volume and
            // frequency range — not the 16 kHz downsampled path the classifier uses.
            let fmt = audioService.inputFormat ?? AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioMonitorService.targetSampleRate,
                channels: 1,
                interleaved: false
            )!
            let path = clipRecorder.beginClip(
                sessionID:    activeSession?.id ?? UUID(),
                eventID:      id,
                nativePreRoll: audioService.nativePreRoll,
                inputFormat:  fmt,
                captureFrom:  captureFrom
            )
            clipOpen = path != nil
            if let p = path {
                sessionStore?.updateEventAudioPath(p, eventID: id)
            }

        case .snoreOnset:
            break

        case .snoreEnded(let id, let at, let brpm, let peakDB, let avgDB):
            activeSnoreEpisode = false
            // Bout ended at gap expiry — stop alarm/notifications now (do not debounce with clearDelay).
            alertManager.clearAfterSnoreBoutEnded()
            if clipOpen {
                let relativePath = clipRecorder.endClip()
                clipOpen = false
                if let p = relativePath {
                    sessionStore?.updateEventAudioPath(p, eventID: id)
                }
            }
            // Capture the same harmonic shown as the red marker on the live spectrum.
            let rumbleHz = AudioMath.brpmHarmonicHighlightHz(brpm: brpm) ?? 0
            sessionStore?.endEvent(id: id, at: at, brpm: brpm, peakDB: peakDB,
                                   avgDB: avgDB, rumbleFrequencyHz: rumbleHz)
            currentBRPM   = brpm
            brpmAvailable = brpm > 0
            activeEventID = nil

        case .brpmUpdated(let brpm):
            currentBRPM   = brpm
            brpmAvailable = true
        }
    }

    private func handleAlertPhase(_ phase: AlertPhase) {
        switch phase {
        case .notified:
            guard sessionPushEnabled else { return }
            notifications.scheduleSnoringAlert()
            startPushRepeatLoop()

        case .alarming:
            pushRepeatTask?.cancel()
            pushRepeatTask = nil
            guard sessionSoundEnabled else { return }
            startAlarmVolumeRamp()

        case .idle, .cleared:
            pushRepeatTask?.cancel()
            pushRepeatTask = nil
            alarmRampTask?.cancel()
            alarmRampTask = nil
            alarmPlayer.stop()
            notifications.cancelSnoringAlert()
            activeSnoreEpisode = false
            isEpisodeConfirmed = false
            currentBRPM       = 0
            brpmAvailable     = false
            detector.resetForNewEpisode()
        }
    }

    /// Re-sends push notifications on an interval while still in `.notified` (snoring continues).
    private func startPushRepeatLoop() {
        pushRepeatTask?.cancel()
        guard sessionPushRepeatEnabled, sessionPushEnabled else { return }
        let interval = max(2, sessionPushRepeatInterval)
        pushRepeatTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard isMonitoring, alertPhase == .notified else { break }
                notifications.scheduleSnoringAlertRepeat()
            }
        }
    }

    /// Every 2 s raise playback toward `alarmVolume` in 20% steps (burst cadence + escalation).
    private func startAlarmVolumeRamp() {
        alarmRampTask?.cancel()
        let maxVol = alertManager.config.alarmVolume
        alarmRampTask = Task { @MainActor in
            var step = 0
            while !Task.isCancelled {
                guard isMonitoring else { break }
                let fraction = min(1.0, 0.2 * Float(step + 1))
                let vol = maxVol * fraction
                alarmPlayer.play(volume: vol)
                step += 1
                try? await Task.sleep(for: .seconds(Self.alarmVolumeStepInterval))
                guard alertPhase == .alarming else { break }
            }
        }
    }

    /// Ends an in-flight AAC encode and persists the SwiftData row when stopping mid-snore bout.
    private func finalizeOpenClipAndEventIfInterrupted() {
        guard let id = activeEventID else { return }
        if clipOpen {
            let relativePath = clipRecorder.endClip()
            clipOpen = false
            if let p = relativePath {
                sessionStore?.updateEventAudioPath(p, eventID: id)
            }
        }
        let peak = min(Float(0), max(currentDB, -160))
        let rumbleHz = AudioMath.brpmHarmonicHighlightHz(brpm: currentBRPM) ?? 0
        sessionStore?.endEvent(id: id, at: Date(), brpm: max(0, currentBRPM), peakDB: peak,
                               avgDB: peak, rumbleFrequencyHz: rumbleHz)
        activeEventID = nil
    }
}