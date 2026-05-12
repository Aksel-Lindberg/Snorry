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
    /// True while tearing down audio pipelines and finalizing SwiftData — UI shows a blocking overlay.
    var isStoppingMonitoring = false

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
    private var monitorTask: Task<Void, Never>?
    private var classifierTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var elapsedTimer: Task<Void, Never>?
    private var timelineTimer: Task<Void, Never>?
    /// Fires repeated push notifications while in `.notified`.
    private var pushRepeatTask: Task<Void, Never>?
    /// Hard-stops the sound alarm after 5 s while the phone is locked (`applicationState` ≠ active).
    private var lockScreenAlarmCapTask: Task<Void, Never>?

    /// Copied from settings at session start (alert UI / playback).
    private var sessionPushEnabled = true
    private var sessionSoundEnabled = true
    private var sessionPushRepeatEnabled = false
    private var sessionPushRepeatInterval: TimeInterval = 60

    /// Restored when unlocking — snapshot from `startMonitoring()`.
    private var savedDetectorConfirmedGap: TimeInterval = 5
    private var savedAlertClearDelay: TimeInterval = 3

    /// Held only for removal in `deinit` (nonisolated) — tokens are thread-safe opaque handles.
    nonisolated(unsafe) private var lockScreenBGObserver: NSObjectProtocol?
    nonisolated(unsafe) private var lockScreenFGObserver: NSObjectProtocol?
    nonisolated(unsafe) private var alertSettingsSaveObserver: NSObjectProtocol?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.spectrumAnalyzer = LiveSpectrumAnalyzer(bandCount: spectrumBandCount)
        sessionStore = SessionStore(context: modelContext)
        checkPermissions()

        let nc = NotificationCenter.default
        lockScreenBGObserver = nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyLockScreenDetectorTuning()
            }
        }
        lockScreenFGObserver = nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restoreLockScreenDetectorTuning()
            }
        }

        alertSettingsSaveObserver = nc.addObserver(
            forName: .snorryAlertSettingsDidSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reapplySnoreDetectionFromSavedSettings()
            }
        }
    }

    deinit {
        if let lockScreenBGObserver {
            NotificationCenter.default.removeObserver(lockScreenBGObserver)
        }
        if let lockScreenFGObserver {
            NotificationCenter.default.removeObserver(lockScreenFGObserver)
        }
        if let alertSettingsSaveObserver {
            NotificationCenter.default.removeObserver(alertSettingsSaveObserver)
        }
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

        // Snapshot the active alert configuration onto the session for analytics.
        session.snapshotPushEnabled    = settings.pushNotificationEnabled
        session.snapshotSoundEnabled   = settings.soundAlarmEnabled
        session.snapshotAlarmStyleRaw  = settings.alarmStyleRaw

        sessionPushEnabled          = settings.pushNotificationEnabled
        sessionSoundEnabled         = settings.soundAlarmEnabled
        // Repeat push notifications are always enabled; interval remains user-configurable.
        sessionPushRepeatEnabled    = true
        sessionPushRepeatInterval   = settings.pushRepeatIntervalSeconds

        // Push notification delay is fixed; sound alarm delay is user-configurable.
        alertManager.config.notifyDelay       = 2
        alertManager.config.soundAlarmAfter   = settings.soundAlarmAfterSeconds
        // Match alert clear delay to the detector gap so the alert machine never races ahead.
        alertManager.config.clearDelay        = 3
        alertManager.config.alarmVolume       = settings.alarmVolume
        alertManager.config.pushEnabled       = settings.pushNotificationEnabled
        alertManager.config.soundEnabled      = settings.soundAlarmEnabled

        // Pending (unconfirmed) episodes are discarded after 3 s of silence.
        // Confirmed events use the longer hysteresis window to bridge between individual
        // snores and avoid premature fragmentation of a single bout.
        detector.gapTolerance          = 3
        detector.confirmedGapTolerance = 5
        savedDetectorConfirmedGap      = detector.confirmedGapTolerance
        savedAlertClearDelay           = alertManager.config.clearDelay

        // Alarm tone style for this session.
        alarmPlayer.setStyle(AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic)

        applySnoreDetectionTuning(sensitivity: settings.snoringDetectionSensitivity)

        startTasks()
    }

    /// Foreground: SoundAnalysis confidence + onset dB. Background / lock: RMS gate (`energyFallbackThresholdDB`).
    private func applySnoreDetectionTuning(sensitivity: Double) {
        SnoreDetectionTuning.apply(
            sensitivityLevel: sensitivity,
            classifier: classifier,
            detector: detector
        )
    }

    /// After Settings save while monitoring — keeps classifier + detector aligned with stored sensitivity.
    private func reapplySnoreDetectionFromSavedSettings() {
        guard isMonitoring else { return }
        let settings = AlertSettings.load(context: modelContext)
        applySnoreDetectionTuning(sensitivity: settings.snoringDetectionSensitivity)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        // Close any per-event AAC file and close the SwiftData row if monitoring stops mid-snore.
        finalizeOpenClipAndEventIfInterrupted()

        cancelTasks()
        cancelLockScreenAlarmCapTask()
        audioService.stop()
        classifier.stop()
        detector.stop()
        alertManager.stop()
        alarmPlayer.stop()
        notifications.cancelSnoringAlert()

        sessionStore?.finalizeSession()
        activeSession = nil
        activeEventID = nil

        isMonitoring       = false
        isSnoring          = false
        isEpisodeConfirmed = false
        alertPhase         = .idle
        currentBRPM        = 0
        brpmAvailable      = false

        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Lets SwiftUI paint a “Saving session…” overlay before heavy teardown + SwiftData finalize.
    func stopMonitoringAsync() async {
        guard isMonitoring, !isStoppingMonitoring else { return }
        isStoppingMonitoring = true
        await Task.yield()
        defer { isStoppingMonitoring = false }
        stopMonitoring()
    }

    // MARK: Async pipelines

    private func startTasks() {
        // 1. Consume AudioMonitorService ticks → classifier + detector + clip recorder
        //
        // Must not run on the main actor: when the phone is locked, iOS deprioritizes UI threads and
        // `SnoreClassifier` + `SnoreEventDetector` would stall while audio capture continues — leaving
        // snore detection “dead” until the device unlocks. Processing at `.userInitiated` keeps the
        // pipeline aligned with background audio.
        let audioRef = audioService
        let classifierRef = classifier
        let detectorRef = detector
        let spectrumRef = spectrumAnalyzer
        let clipsRef = clipRecorder
        let analysisRate = AudioMonitorService.targetSampleRate

        monitorTask = Task(priority: .userInitiated) { [weak self] in
            guard let stream = audioRef.stream else { return }
            for await tick in stream {
                guard !Task.isCancelled else { break }

                let time = AVAudioTime(sampleTime: 0, atRate: analysisRate)
                classifierRef.analyze(buffer: tick.buffer, at: time)
                detectorRef.feed(tick: tick)

                // `ClipRecorder.write` no-ops when no file is open; safe every tick (clip IO is locked).
                clipsRef.write(buffer: tick.nativeBuffer)

                let rawBands = spectrumRef.bands(fromPCM: tick.buffer)

                await MainActor.run { [weak self] in
                    guard let self, self.isMonitoring else { return }

                    if self.spectrumBands.count != rawBands.count {
                        self.spectrumBands = rawBands
                    } else {
                        let smoothingAlpha: Float = 0.38
                        for bandIndex in rawBands.indices {
                            self.spectrumBands[bandIndex] = smoothingAlpha * rawBands[bandIndex]
                                + (1 - smoothingAlpha) * self.spectrumBands[bandIndex]
                        }
                    }

                    self.currentDB = tick.dBFS
                    if tick.dBFS > (self.activeSession?.peakDB ?? -160) {
                        self.activeSession?.peakDB = tick.dBFS
                    }
                }
            }
        }

        // 2. Classifier result → detector (same priority as the tick loop)
        classifierTask = Task(priority: .userInitiated) { [weak self] in
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
                // Keep alerts alive briefly between breaths, then end within 2 s of quiet.
                updateAlertSnoringState()
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
        pushRepeatTask?.cancel(); pushRepeatTask = nil
    }

    // MARK: Event handling

    private func handle(detectorEvent event: DetectorEvent) {
        switch event {
        case .snoringActive(let active):
            isSnoring = active
            updateAlertSnoringState()

        case .snoreStarted(let id, let at, let captureFrom):
            activeEventID      = id
            snoreEventCount   += 1
            isEpisodeConfirmed = true
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
                sessionID: activeSession?.id ?? UUID(),
                eventID: id,
                nativePreRoll: audioService.nativePreRoll,
                inputFormat: fmt,
                captureFrom: captureFrom
            )
            clipOpen = path != nil
            if let clipPath = path {
                sessionStore?.updateEventAudioPath(clipPath, eventID: id)
            }

        case .snoreOnset:
            break

        case .snoreEnded(let id, let at, let brpm, let peakDB, let avgDB):
            var clipRelativePath: String?
            if clipOpen {
                let relativePath = clipRecorder.endClip()
                clipOpen = false
                if let clipPath = relativePath {
                    sessionStore?.updateEventAudioPath(clipPath, eventID: id)
                    clipRelativePath = clipPath
                }
            }
            // Breath-tempo harmonic (live spectrum red marker); distinct from clip `spectralPeakHz`.
            let rumbleHz = AudioMath.brpmHarmonicHighlightHz(brpm: brpm) ?? 0
            sessionStore?.endEvent(id: id, at: at, brpm: brpm, peakDB: peakDB,
                                   avgDB: avgDB, rumbleFrequencyHz: rumbleHz)
            if let rel = clipRelativePath {
                scheduleClipSpectralAnalysis(relativePath: rel, eventID: id)
            }
            currentBRPM   = brpm
            brpmAvailable = brpm > 0
            activeEventID = nil
            // Stop alarm/push exactly when this confirmed snore event ends.
            alertManager.clearAfterSnoreBoutEnded()

        case .brpmUpdated(let brpm):
            currentBRPM   = brpm
            brpmAvailable = true
        }
    }

    /// Runs the alert state machine from confirmed episode state.
    ///
    /// Uses live `isSnoring` after confirmation so **silence** reaches `AlertManager` while locked.
    /// Feeding only `isEpisodeConfirmed` keeps `update(isSnoring: true)` for the whole bout, so the
    /// alarm never sees quiet time and won't clear until `clearDelay` — which never ran — causing
    /// the tone to loop after snoring stops on the lock screen.
    private func updateAlertSnoringState() {
        let sustainedForAlerts = isEpisodeConfirmed && isSnoring
        alertManager.update(isSnoring: sustainedForAlerts, at: Date())
    }

    /// Bout-end tuning while locked; also uses a **5 s** silence window before alerts clear (matches lock-screen alarm cap default).
    private func applyLockScreenDetectorTuning() {
        guard isMonitoring else { return }
        detector.confirmedGapTolerance = 2.5
        alertManager.config.clearDelay = 5
        // If the sound alarm was already playing before the phone locked, start the 5 s cap from now.
        if alertPhase == .alarming, sessionSoundEnabled {
            scheduleLockScreenAlarmAutoStopIfNeeded()
        }
    }

    private func restoreLockScreenDetectorTuning() {
        guard isMonitoring else { return }
        cancelLockScreenAlarmCapTask()
        detector.confirmedGapTolerance = savedDetectorConfirmedGap
        alertManager.config.clearDelay = savedAlertClearDelay
    }

    private func cancelLockScreenAlarmCapTask() {
        lockScreenAlarmCapTask?.cancel()
        lockScreenAlarmCapTask = nil
    }

    /// When locked, the alarm tone stops automatically after **5 seconds** (then alerts reset like a bout end).
    private func scheduleLockScreenAlarmAutoStopIfNeeded() {
        cancelLockScreenAlarmCapTask()
        guard UIApplication.shared.applicationState != .active else { return }

        lockScreenAlarmCapTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, isMonitoring else { return }
            guard alertPhase == .alarming else { return }

            alarmPlayer.stop()
            alertManager.clearAfterSnoreBoutEnded()
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
            // Re-assert speaker routing before playing — the session can lose its
            // port override if interrupted by a system sound, phone call, etc.
            AudioSessionManager.shared.activateSpeakerForAlarm()
            let selectedVolume = max(0.10, min(1.0, alertManager.config.alarmVolume))
            // Jump straight to the configured volume — no fade-in for a real alarm.
            alarmPlayer.playImmediate(volume: selectedVolume)
            scheduleLockScreenAlarmAutoStopIfNeeded()

        case .idle, .cleared:
            cancelLockScreenAlarmCapTask()
            pushRepeatTask?.cancel()
            pushRepeatTask = nil
            alarmPlayer.stop()
            notifications.cancelSnoringAlert()
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
        let interval = max(1, sessionPushRepeatInterval)
        pushRepeatTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard isMonitoring, alertPhase == .notified else { break }
                notifications.scheduleSnoringAlertRepeat()
            }
        }
    }

    /// Ends an in-flight AAC encode and persists the SwiftData row when stopping mid-snore bout.
    private func finalizeOpenClipAndEventIfInterrupted() {
        guard let id = activeEventID else { return }
        var clipRelativePath: String?
        if clipOpen {
            let relativePath = clipRecorder.endClip()
            clipOpen = false
            if let clipPath = relativePath {
                sessionStore?.updateEventAudioPath(clipPath, eventID: id)
                clipRelativePath = clipPath
            }
        }
        let peak = min(Float(0), max(currentDB, -160))
        let rumbleHz = AudioMath.brpmHarmonicHighlightHz(brpm: currentBRPM) ?? 0
        sessionStore?.endEvent(id: id, at: Date(), brpm: max(0, currentBRPM), peakDB: peak,
                               avgDB: peak, rumbleFrequencyHz: rumbleHz)
        if let rel = clipRelativePath {
            scheduleClipSpectralAnalysis(relativePath: rel, eventID: id)
        }
        activeEventID = nil
    }

    /// FFT-based rumble peak from the saved clip (background); updates `spectralPeakHz`.
    private func scheduleClipSpectralAnalysis(relativePath: String, eventID: UUID) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = support.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let context = modelContext
        let id = eventID

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            let peakHz: Double? = await Task.detached(priority: .utility) {
                try? SnoreClipSpectralAnalyzer.dominantPeakHz(fileURL: url)
            }.value
            guard let hz = peakHz else { return }
            SessionStore(context: context).setSpectralPeakHz(hz, eventID: id)
        }
    }
}