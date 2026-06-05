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
    /// Short status shown in the stopping overlay; changes during classification phase.
    var stoppingStatusMessage: String = "Finishing audio and storing events."

    /// Three-state detection status for the UI status badge.
    enum DetectionPhase { case quiet, detecting, confirmed }
    var detectionPhase: DetectionPhase {
        if isSnoreEventActive { return .confirmed }
        if isSnoring           { return .detecting }
        return .quiet
    }

    /// True between `.snoreStarted` and `.snoreEnded` while an event is being logged.
    var isSnoreEventActive: Bool { activeEventID != nil }

    /// Lowest harmonic of the respiratory tempo that falls in the snore-heavy band (~85–2800 Hz).
    var spectrumBRPMHighlightHz: Double? {
        guard isSnoreEventActive, brpmAvailable, currentBRPM > 0 else { return nil }
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
    /// True once push or sound has fired for the current `activeEventID` — prevents re-alarming mid-bout.
    private var alertDeliveredForCurrentEvent = false
    /// Lock-screen only: CPU SoundAnalysis must confirm snoring on the clip before arming alarms.
    private var backgroundSnoringVerifiedForAlarm = true
    private var backgroundAlarmVerificationTask: Task<Void, Never>?
    /// Stops the audible alarm a fixed interval after it begins.
    private var alarmAutoStopTask: Task<Void, Never>?
    /// When continuous background snoring began (RMS + rumble path) — used for the 3 s alarm delay.
    private var backgroundContinuousSnoringSince: Date?
    /// Brief classifier dropouts during a bout do not reset the 3 s snoring clock.
    private var backgroundSnoringInactiveSince: Date?
    private let backgroundSnoringGapBridge: TimeInterval = 1.25
    private var isBackgroundMonitoringProfileActive = false
    private var savedForegroundMinConfirm: TimeInterval = 5
    private var savedForegroundNotifyDelay: TimeInterval = 2
    private var savedForegroundSoundAlarmAfter: TimeInterval = 10
    private var monitorTask: Task<Void, Never>?
    private var classifierTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var elapsedTimer: Task<Void, Never>?
    private var timelineTimer: Task<Void, Never>?
    /// Fires repeated push notifications while in `.notified`.
    private var pushRepeatTask: Task<Void, Never>?
    /// Set when an alarm reconfigures the audio session; cleared after monitoring is restored.
    private var needsMonitoringRestoreAfterAlarm = false
    private var monitoringStartedAt: Date?
    private var lastPipelineRecoveryAt: Date?

    /// Copied from settings at session start (alert UI / playback).
    private var sessionPushEnabled = true
    private var sessionSoundEnabled = true
    private var sessionPushRepeatEnabled = false
    private var sessionPushRepeatInterval: TimeInterval = 60

    /// Held only for removal in `deinit` (nonisolated) — tokens are thread-safe opaque handles.
    @ObservationIgnored
    nonisolated(unsafe) private var lockScreenBGObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var lockScreenFGObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var alertSettingsSaveObserver: NSObjectProtocol?

    private let modelContext: ModelContext

    /// Lock-screen / background timing — faster confirm, fixed 3 s alarm, strict 10 s event end.
    private enum BackgroundMonitoring {
        static let eventConfirmSeconds: TimeInterval = 3
        static let eventEndSilenceSeconds: TimeInterval = 10
        static let alarmDelaySeconds: TimeInterval = 3
        static let alarmPlayDurationSeconds: TimeInterval = 5
        static let clipVerificationDelaySeconds: TimeInterval = 4.5
    }

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
            Task { @MainActor [weak self] in
                guard let self else { return }
                markBackgroundRecordingPeriodIfNeeded()
                handleEnteredBackgroundDuringMonitoring()
            }
        }
        lockScreenFGObserver = nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await syncNotificationAuthorizationFromSystem()
                handleReturnedToForegroundDuringMonitoring()
            }
        }

        alertSettingsSaveObserver = nc.addObserver(
            forName: .snorryAlertSettingsDidSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                reapplyAlertAndDetectionFromSavedSettings()
                await syncNotificationAuthorizationFromSystem()
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

    /// Reads notification permission from the system without prompting (prompt happens in Settings when enabling push).
    func syncNotificationAuthorizationFromSystem() async {
        await notifications.refreshAuthorizationState()
        notificationAuthorized = notifications.isAuthorized
    }

    // MARK: Start / Stop

    func startMonitoring() {
        guard !isMonitoring,
              !isStoppingMonitoring,
              microphonePermission == .granted,
              let store = sessionStore else { return }

        // Clear any orphaned tasks from a prior session that did not tear down cleanly.
        cancelTasks()

        UIApplication.shared.isIdleTimerDisabled = true

        isMonitoring = true
        isSnoring = false
        elapsedSeconds = 0
        snoreEventCount = 0
        spectrumBands = []
        timelinePoints = []
        alertPhase = .idle
        needsMonitoringRestoreAfterAlarm = false
        monitoringStartedAt = nil
        lastPipelineRecoveryAt = nil

        let session = store.startSession()
        activeSession = session

        let settings = AlertSettings.load(context: modelContext)
        applyMonitoringSettings(settings, to: session)

        // Release any clip-replay session left open from session detail or settings preview.
        AudioSessionManager.shared.endClipReplaySession(restoreMonitoring: false)

        do {
            classifier.start()
            classifier.setLockScreenEnergyMode(false)
            detector.start()
            alertManager.start()
            try audioService.start()
        } catch {
            audioService.stop()
            classifier.stop()
            detector.stop()
            alertManager.stop()
            sessionStore?.finalizeSession()
            activeSession = nil
            isMonitoring = false
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        monitoringStartedAt = Date()
        startTasks()

        AppAnalytics.logMonitoringStarted(
            pushEnabled: settings.pushNotificationEnabled,
            soundEnabled: settings.soundAlarmEnabled
        )
    }

    /// Applies alert, detector, and classifier tuning before the mic pipeline starts.
    private func applyMonitoringSettings(_ settings: AlertSettings, to session: SnoreSession) {
        session.snapshotPushEnabled    = settings.pushNotificationEnabled
        session.snapshotSoundEnabled   = settings.soundAlarmEnabled
        session.snapshotAlarmStyleRaw  = settings.alarmStyleRaw

        sessionPushEnabled        = settings.pushNotificationEnabled
        sessionSoundEnabled       = settings.soundAlarmEnabled
        sessionPushRepeatEnabled    = true
        sessionPushRepeatInterval   = settings.pushRepeatIntervalSeconds

        alertManager.config.notifyDelay       = 2
        alertManager.config.soundAlarmAfter   = settings.soundAlarmAfterSeconds
        alertManager.config.clearDelay        = 3
        alertManager.config.alarmVolume       = settings.alarmVolume
        alertManager.config.pushEnabled       = settings.pushNotificationEnabled
        alertManager.config.soundEnabled      = settings.soundAlarmEnabled

        detector.gapTolerance                      = 3
        detector.confirmedGapTolerance             = 10
        detector.minContinuousSnoringBeforeConfirm = 5

        alarmPlayer.setStyle(AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic)
        applySnoreDetectionTuning(sensitivity: settings.snoringDetectionSensitivity)

        savedForegroundMinConfirm = detector.minContinuousSnoringBeforeConfirm
        savedForegroundNotifyDelay = alertManager.config.notifyDelay
        savedForegroundSoundAlarmAfter = settings.soundAlarmAfterSeconds

        if requiresBackgroundAlarmVerification {
            applyBackgroundMonitoringProfile(soundAlarmAfter: settings.soundAlarmAfterSeconds)
            backgroundSnoringVerifiedForAlarm = false
            if isSnoring {
                backgroundContinuousSnoringSince = Date()
            }
        }
    }

    /// Foreground: SoundAnalysis confidence + onset dB. Background / lock: RMS gate (`energyFallbackThresholdDB`).
    private func applySnoreDetectionTuning(sensitivity: Double) {
        SnoreDetectionTuning.apply(
            sensitivityLevel: sensitivity,
            classifier: classifier,
            detector: detector
        )
    }

    /// After Settings save while monitoring — refresh alert channels and snore tuning.
    private func reapplyAlertAndDetectionFromSavedSettings() {
        guard isMonitoring else { return }
        let settings = AlertSettings.load(context: modelContext)

        sessionPushEnabled        = settings.pushNotificationEnabled
        sessionSoundEnabled       = settings.soundAlarmEnabled
        sessionPushRepeatInterval = settings.pushRepeatIntervalSeconds
        alertManager.config.pushEnabled     = settings.pushNotificationEnabled
        alertManager.config.soundEnabled    = settings.soundAlarmEnabled
        alertManager.config.soundAlarmAfter = settings.soundAlarmAfterSeconds
        alertManager.config.alarmVolume     = settings.alarmVolume
        alarmPlayer.setStyle(AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic)

        applySnoreDetectionTuning(sensitivity: settings.snoringDetectionSensitivity)

        if isBackgroundMonitoringProfileActive {
            applyBackgroundMonitoringProfile(soundAlarmAfter: settings.soundAlarmAfterSeconds)
        } else {
            alertManager.config.soundAlarmAfter = settings.soundAlarmAfterSeconds
        }
    }

    /// Synchronous teardown — used by crash/orphan recovery paths.
    /// Does not run post-stop classification; call `stopMonitoringAsync()` from the UI instead.
    func stopMonitoring() {
        guard isMonitoring else { return }

        teardownPipelines()
        sessionStore?.finalizeSession()
        resetMonitoringState()
    }

    // MARK: Private stop helpers

    /// Stops all active audio pipelines, tasks, and notification state.
    private func teardownPipelines() {
        // Close any per-event AAC file and close the SwiftData row if monitoring stops mid-snore.
        finalizeOpenClipAndEventIfInterrupted()

        cancelTasks()
        cancelAlarmAutoStop()
        audioService.stop()
        classifier.stop()
        detector.stop()
        alertManager.stop()
        alarmPlayer.stop()
        notifications.cancelSnoringAlert()
    }

    /// Clears live-monitoring published state after teardown + finalize.
    private func resetMonitoringState() {
        activeSession = nil
        activeEventID = nil
        alertDeliveredForCurrentEvent = false
        backgroundSnoringVerifiedForAlarm = true
        backgroundContinuousSnoringSince = nil
        backgroundSnoringInactiveSince = nil
        cancelBackgroundAlarmVerification()
        cancelAlarmAutoStop()

        isMonitoring       = false
        isSnoring          = false
        isEpisodeConfirmed = false
        alertPhase         = .idle
        needsMonitoringRestoreAfterAlarm = false
        monitoringStartedAt = nil
        lastPipelineRecoveryAt = nil
        currentBRPM        = 0
        brpmAvailable      = false

        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Async stop invoked by the Stop Monitoring button.
    /// Tears down pipelines, classifies clips on background-recorded nights, then finalizes.
    func stopMonitoringAsync() async {
        guard isMonitoring, !isStoppingMonitoring else { return }
        isStoppingMonitoring = true
        stoppingStatusMessage = "Finishing audio and storing events."
        await Task.yield()
        defer { isStoppingMonitoring = false }

        teardownPipelines()

        // Classify clips when the device was locked/backgrounded at any point this session.
        if let session = activeSession,
           session.hadBackgroundRecordingPeriod == true {
            let completedEvents = session.events.filter { $0.endDate != nil }
            if !completedEvents.isEmpty {
                stoppingStatusMessage = "Classifying sounds…"
                await Task.yield()
                let support = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first!
                await SessionClipSoundClassifier.classifyAll(
                    events: completedEvents,
                    applicationSupport: support,
                    preserveDetectorSnoreEvents: true
                )
            }
        }

        let durationSeconds = elapsedSeconds
        sessionStore?.finalizeSession()
        resetMonitoringState()
        AppAnalytics.logMonitoringStopped(durationSeconds: durationSeconds)
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
                recoverAudioPipelineIfStalled()
                if requiresBackgroundAlarmVerification {
                    evaluateBackgroundAlarmEligibility()
                }
                // Drive alert silence detection at 1 Hz (alarm clears after 3 s without snoring).
                updateAlertSnoringState()
                // Persist waveform sample every second
                sessionStore?.addWaveformSample(
                    dBFS: currentDB,
                    brpm: currentBRPM,
                    isSnoringActive: isSnoreEventActive && isSnoring
                )
                timelinePoints.append(TimelinePoint(
                    time: Date(),
                    dBFS: currentDB,
                    brpm: currentBRPM,
                    isSnoring: isSnoreEventActive && isSnoring
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
        cancelBackgroundAlarmVerification()
        cancelAlarmAutoStop()
    }

    /// Restarts the mic tap when ticks stop arriving (e.g. after a failed route reconfigure).
    private func recoverAudioPipelineIfStalled() {
        guard let startedAt = monitoringStartedAt else { return }
        guard Date().timeIntervalSince(startedAt) > 4 else { return }
        guard Date().timeIntervalSince(lastPipelineRecoveryAt ?? .distantPast) > 10 else { return }

        let lastTick = audioService.lastTickTime
        let stalled = lastTick.map { Date().timeIntervalSince($0) > 3 } ?? true
        guard stalled else { return }

        lastPipelineRecoveryAt = Date()
        audioService.reconfigureAfterRouteChange()
    }

    // MARK: Event handling

    private func handle(detectorEvent event: DetectorEvent) {
        switch event {
        case .snoringActive(let active):
            isSnoring = active
            if requiresBackgroundAlarmVerification {
                trackBackgroundContinuousSnoring(active: active)
            }
            updateAlertSnoringState()

        case .snoreStarted(let id, let at, let captureFrom):
            activeEventID      = id
            snoreEventCount   += 1
            isEpisodeConfirmed = true
            alertDeliveredForCurrentEvent = false
            if requiresBackgroundAlarmVerification {
                armBackgroundAlertsIfVerified()
            } else {
                backgroundSnoringVerifiedForAlarm = true
                alertManager.update(isSnoring: true, at: Date())
            }
            // Fresh BRPM estimation for each new detector bout / event.
            currentBRPM       = 0
            brpmAvailable     = false
            sessionStore?.beginEvent(id: id, at: at)
            if isBackgroundMonitoringProfileActive || requiresBackgroundAlarmVerification {
                sessionStore?.setSoundKind(.snoring, eventID: id)
            }

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
            if requiresBackgroundAlarmVerification {
                startBackgroundAlarmVerification(eventID: id)
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
            if isBackgroundMonitoringProfileActive
                || activeSession?.hadBackgroundRecordingPeriod == true {
                sessionStore?.setSoundKind(.snoring, eventID: id)
            }
            if let rel = clipRelativePath {
                scheduleClipSpectralAnalysis(relativePath: rel, eventID: id)
            }
            activeEventID = nil
            cancelBackgroundAlarmVerification()
            cancelAlarmAutoStop()
            // Return UI to Quiet
            isEpisodeConfirmed = false
            brpmAvailable = false
            currentBRPM = 0
            // Only force-clear when an alert already fired; otherwise let the 1 Hz loop
            // finish the notify/sound delay (short test clips used to cancel too early).
            if alertPhase == .notified || alertPhase == .alarming {
                alertManager.clearAfterSnoreBoutEnded()
            }

        case .brpmUpdated(let brpm):
            currentBRPM   = brpm
            brpmAvailable = true
        }
    }

    /// Runs the alert state machine from confirmed episode state.
    ///
    /// Before an alert fires, keep the escalation clock running through brief classifier dropouts.
    /// Once push or sound has fired for this event, pass live classifier state only while the alarm
    /// is still playing; after it clears, do not re-arm until the next `.snoreStarted`.
    private func updateAlertSnoringState() {
        let alertAlreadyActive = alertPhase == .notified || alertPhase == .alarming

        let snoringForAlerts: Bool
        if alertAlreadyActive {
            snoringForAlerts = isSnoring
        } else if alertDeliveredForCurrentEvent {
            snoringForAlerts = false
        } else if requiresBackgroundAlarmVerification {
            // Lock screen: escalate after 3 s continuous RMS + rumble snoring (clip ML may cancel later).
            snoringForAlerts = isSnoring && backgroundSnoringVerifiedForAlarm
        } else if !isEpisodeConfirmed {
            snoringForAlerts = false
        } else {
            snoringForAlerts = true
        }

        alertManager.update(isSnoring: snoringForAlerts, at: Date())
    }

    /// True while the app is locked or backgrounded — RMS fallback replaces live SoundAnalysis.
    private var requiresBackgroundAlarmVerification: Bool {
        UIApplication.shared.applicationState != .active
    }

    /// When the device locks mid-session, apply lock-screen detection / alarm timing.
    private func handleEnteredBackgroundDuringMonitoring() {
        guard isMonitoring else { return }
        let settings = AlertSettings.load(context: modelContext)
        applyBackgroundMonitoringProfile(soundAlarmAfter: settings.soundAlarmAfterSeconds)
        backgroundSnoringVerifiedForAlarm = false
        if isSnoring {
            backgroundContinuousSnoringSince = Date()
            evaluateBackgroundAlarmEligibility()
        }
        if let id = activeEventID, !alertDeliveredForCurrentEvent {
            startBackgroundAlarmVerification(eventID: id)
        }
    }

    /// Foreground SoundAnalysis resumes — restore user alert timing and faster bout confirm rules.
    private func handleReturnedToForegroundDuringMonitoring() {
        guard isMonitoring else { return }
        applyForegroundMonitoringProfile()
        if isEpisodeConfirmed, activeEventID != nil, !backgroundSnoringVerifiedForAlarm {
            cancelBackgroundAlarmVerification()
            backgroundSnoringVerifiedForAlarm = true
            armBackgroundAlertsIfVerified()
        }
        updateAlertSnoringState()
    }

    private func applyBackgroundMonitoringProfile(soundAlarmAfter: TimeInterval) {
        isBackgroundMonitoringProfileActive = true
        classifier.setLockScreenEnergyMode(true)
        detector.minContinuousSnoringBeforeConfirm = BackgroundMonitoring.eventConfirmSeconds
        detector.confirmedGapTolerance = BackgroundMonitoring.eventEndSilenceSeconds
        detector.strictConfirmedSilenceGap = true
        alertManager.config.notifyDelay = BackgroundMonitoring.alarmDelaySeconds
        alertManager.config.soundAlarmAfter = BackgroundMonitoring.alarmDelaySeconds
    }

    private func applyForegroundMonitoringProfile() {
        isBackgroundMonitoringProfileActive = false
        classifier.setLockScreenEnergyMode(false)
        detector.minContinuousSnoringBeforeConfirm = savedForegroundMinConfirm
        detector.confirmedGapTolerance = BackgroundMonitoring.eventEndSilenceSeconds
        detector.strictConfirmedSilenceGap = false
        alertManager.config.notifyDelay = savedForegroundNotifyDelay
        alertManager.config.soundAlarmAfter = savedForegroundSoundAlarmAfter
        backgroundContinuousSnoringSince = nil
        backgroundSnoringInactiveSince = nil
    }

    /// Marks 3 s of continuous lock-screen snoring and back-dates the alert escalation clock to bout onset.
    private func trackBackgroundContinuousSnoring(active: Bool) {
        if active {
            backgroundSnoringInactiveSince = nil
            if backgroundContinuousSnoringSince == nil {
                backgroundContinuousSnoringSince = Date()
            }
            evaluateBackgroundAlarmEligibility()
        } else {
            if backgroundSnoringInactiveSince == nil {
                backgroundSnoringInactiveSince = Date()
            }
            guard let pauseStart = backgroundSnoringInactiveSince else { return }
            if Date().timeIntervalSince(pauseStart) >= backgroundSnoringGapBridge,
               alertPhase == .idle, !alertDeliveredForCurrentEvent {
                backgroundContinuousSnoringSince = nil
                backgroundSnoringVerifiedForAlarm = false
            }
        }
    }

    private func evaluateBackgroundAlarmEligibility(at now: Date = Date()) {
        guard requiresBackgroundAlarmVerification, isSnoring else { return }
        guard let since = backgroundContinuousSnoringSince else { return }
        guard now.timeIntervalSince(since) >= BackgroundMonitoring.alarmDelaySeconds else { return }

        backgroundSnoringVerifiedForAlarm = true
        armBackgroundAlertsIfVerified()
        syncAlertDelivery()
    }

    private func armBackgroundAlertsIfVerified() {
        guard backgroundSnoringVerifiedForAlarm, !alertDeliveredForCurrentEvent else { return }
        guard alertPhase == .idle else { return }
        let anchor = backgroundContinuousSnoringSince ?? Date()
        alertManager.beginEscalation(from: anchor)
        alertManager.update(isSnoring: true, at: Date())
    }

    /// Applies alert side-effects immediately — the async phase stream can lag on lock screen.
    private func syncAlertDelivery() {
        while alertManager.phase != alertPhase {
            let phase = alertManager.phase
            alertPhase = phase
            handleAlertPhase(phase)
        }
    }

    /// Runs CPU SoundAnalysis on the in-progress AAC clip to cancel false-positive lock-screen alarms.
    private func startBackgroundAlarmVerification(eventID: UUID) {
        cancelBackgroundAlarmVerification()
        guard requiresBackgroundAlarmVerification else { return }

        backgroundAlarmVerificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(BackgroundMonitoring.clipVerificationDelaySeconds))
            guard !Task.isCancelled, activeEventID == eventID else { return }

            guard let relativePath = clipRecorder.openClipRelativePath else { return }

            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            let url = support.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return }

            let kind = await SessionClipSoundClassifier.classifyForAlarmVerification(fileURL: url)
            guard !Task.isCancelled, activeEventID == eventID else { return }
            applyBackgroundAlarmVerification(kind, eventID: eventID)
        }
    }

    private func applyBackgroundAlarmVerification(_ kind: SoundEventKind, eventID: UUID) {
        let boutWasAlarmed = alertDeliveredForCurrentEvent
            || alertPhase == .notified
            || alertPhase == .alarming

        if kind == .snoring || boutWasAlarmed {
            // Detector + RMS confirmed this bout; keep it counted as snoring in history.
            sessionStore?.setSoundKind(.snoring, eventID: eventID)
            return
        }

        // Sleep talking / environment with no alert — relabel and suppress future escalation.
        sessionStore?.setSoundKind(kind, eventID: eventID)
        backgroundSnoringVerifiedForAlarm = false
        backgroundContinuousSnoringSince = nil
        backgroundSnoringInactiveSince = nil
        alertManager.update(isSnoring: false, at: Date())
    }

    private func cancelBackgroundAlarmVerification() {
        backgroundAlarmVerificationTask?.cancel()
        backgroundAlarmVerificationTask = nil
    }

    /// Records that the device went to the background during an active session.
    /// This triggers post-stop SoundAnalysis re-classification of recorded clips.
    private func markBackgroundRecordingPeriodIfNeeded() {
        guard isMonitoring, let session = activeSession else { return }
        session.hadBackgroundRecordingPeriod = true
    }

    private func handleAlertPhase(_ phase: AlertPhase) {
        switch phase {
        case .notified:
            alertDeliveredForCurrentEvent = true
            if sessionPushEnabled {
                notifications.scheduleSnoringAlert()
                startPushRepeatLoop()
            } else if sessionSoundEnabled, alertManager.config.soundEnabled {
                // Push disabled — escalate straight to the audible alarm at the 3 s mark.
                let anchor = backgroundContinuousSnoringSince ?? Date()
                alertManager.beginEscalation(from: anchor)
                alertManager.update(isSnoring: true, at: Date())
                syncAlertDelivery()
            }

        case .alarming:
            alertDeliveredForCurrentEvent = true
            pushRepeatTask?.cancel()
            pushRepeatTask = nil
            guard sessionSoundEnabled else { return }
            needsMonitoringRestoreAfterAlarm = true
            // Re-assert output routing before playing — the session can lose its
            // port override if interrupted by a system sound, phone call, etc.
            AudioSessionManager.shared.prepareOutputRouteForAlarm()
            let selectedVolume = max(0.10, min(1.0, alertManager.config.alarmVolume))
            // Jump straight to the configured volume — no fade-in for a real alarm.
            alarmPlayer.playImmediate(volume: selectedVolume)
            scheduleAlarmAutoStop()

        case .idle, .cleared:
            cancelAlarmAutoStop()
            pushRepeatTask?.cancel()
            pushRepeatTask = nil
            alarmPlayer.stop()
            if isMonitoring, needsMonitoringRestoreAfterAlarm {
                AudioSessionManager.shared.restoreMonitoringAfterAlarm()
                needsMonitoringRestoreAfterAlarm = false
            }
            notifications.cancelSnoringAlert()
            // Only tear down the bout when logging has ended — brief pauses mid-event may clear the alarm.
            if activeEventID == nil {
                isEpisodeConfirmed = false
                currentBRPM       = 0
                brpmAvailable     = false
                detector.resetForNewEpisode()
            }
        }
    }

    /// Caps audible alarm playback at 5 s — one short burst per bout.
    private func scheduleAlarmAutoStop() {
        cancelAlarmAutoStop()
        alarmAutoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BackgroundMonitoring.alarmPlayDurationSeconds))
            guard let self, !Task.isCancelled else { return }
            guard alertPhase == .alarming else { return }
            stopActiveAlarmPlayback()
        }
    }

    private func cancelAlarmAutoStop() {
        alarmAutoStopTask?.cancel()
        alarmAutoStopTask = nil
    }

    private func stopActiveAlarmPlayback() {
        alarmPlayer.stop()
        pushRepeatTask?.cancel()
        pushRepeatTask = nil
        notifications.cancelSnoringAlert()
        alertManager.clearAfterSnoreBoutEnded()
        alertPhase = .idle
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