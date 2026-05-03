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
    var isSnoring = false
    var currentDB: Float = -160
    var currentBRPM: Double = 0
    var brpmAvailable = false
    var alertPhase: AlertPhase = .idle
    var elapsedSeconds: Int = 0
    var snoreEventCount = 0
    var recentSession: SnoreSession?

    /// Rolling window of dBFS samples for live waveform (max 300 = ~6 s at 50 fps)
    var waveformBuffer: [Float] = []
    private let waveformMaxCount = 300

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

    private var sessionStore: SessionStore?
    private var activeSession: SnoreSession?
    private var activeEventID: UUID?
    private var currentRelativePath: String?

    private var monitorTask: Task<Void, Never>?
    private var classifierTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var elapsedTimer: Task<Void, Never>?
    private var timelineTimer: Task<Void, Never>?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        elapsedSeconds = 0
        snoreEventCount = 0
        waveformBuffer = []
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
        alertManager.config.notifyDelay      = settings.notifyDelaySeconds
        alertManager.config.audioLowDelay    = settings.audioLowDelaySeconds
        alertManager.config.audioMedDelay    = settings.audioMedDelaySeconds
        alertManager.config.audioHighDelay   = settings.audioHighDelaySeconds
        alertManager.config.clearDelay       = settings.clearDelaySeconds
        alertManager.config.volumeLow        = settings.volumeLow
        alertManager.config.volumeMed        = settings.volumeMed
        alertManager.config.volumeHigh       = settings.volumeHigh

        startTasks()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
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

        isMonitoring = false
        isSnoring = false
        alertPhase = .idle

        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: Async pipelines

    private func startTasks() {
        // 1. Consume AudioMonitorService ticks → feed classifier + detector
        monitorTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = audioService.stream else { return }
            for await tick in stream {
                guard !Task.isCancelled else { break }
                let time = AVAudioTime(sampleTime: 0,
                                      atRate: AudioMonitorService.targetSampleRate)
                classifier.analyze(buffer: tick.buffer, at: time)
                detector.feed(tick: tick)

                // Update live dB + waveform on main actor
                currentDB = tick.dBFS
                let norm = AudioMath.normalisedLevel(tick.dBFS)
                waveformBuffer.append(Float(norm))
                if waveformBuffer.count > waveformMaxCount {
                    waveformBuffer.removeFirst()
                }
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

        // 3. Detector events → clip recorder + store + alert
        detectorTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = detector.stream else { return }
            for await event in stream {
                guard !Task.isCancelled else { break }
                handle(detectorEvent: event)
            }
        }

        // 4. Alert manager phase changes → notification + alarm
        alertTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = alertManager.phaseStream else { return }
            for await phase in stream {
                guard !Task.isCancelled else { break }
                alertPhase = phase
                handleAlertPhase(phase)
            }
        }

        // 5. Elapsed timer (1 Hz)
        elapsedTimer = Task { [weak self] in
            while true {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(1))
                guard let self, isMonitoring else { break }
                elapsedSeconds += 1
                alertManager.update(isSnoring: isSnoring)
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
    }

    // MARK: Event handling

    private func handle(detectorEvent event: DetectorEvent) {
        switch event {
        case .snoringActive(let active):
            isSnoring = active

        case .snoreStarted(let id, let at):
            activeEventID = id
            snoreEventCount += 1
            sessionStore?.beginEvent(id: id, at: at)
            let path = clipRecorder.beginClip(
                sessionID: activeSession?.id ?? UUID(),
                eventID: id,
                preRoll: audioService.preRoll
            )
            if let p = path {
                sessionStore?.updateEventAudioPath(p, eventID: id)
            }

        case .snoreOnset:
            // Write current buffer to clip
            break

        case .snoreEnded(let id, let at, let brpm, let peakDB):
            clipRecorder.endClip()
            sessionStore?.endEvent(id: id, at: at, brpm: brpm, peakDB: peakDB)
            if brpm > 0 { currentBRPM = brpm; brpmAvailable = true }
            activeEventID = nil

        case .brpmUpdated(let brpm):
            currentBRPM = brpm
            brpmAvailable = true
        }
    }

    private func handleAlertPhase(_ phase: AlertPhase) {
        switch phase {
        case .notified:
            notifications.scheduleSnoringAlert()

        case .audioLow:
            alarmPlayer.play(volume: alertManager.config.volumeLow)

        case .audioMedium:
            alarmPlayer.play(volume: alertManager.config.volumeMed)

        case .audioHigh:
            alarmPlayer.play(volume: alertManager.config.volumeHigh)

        case .idle, .cleared:
            alarmPlayer.fadeOut()
            notifications.cancelSnoringAlert()

        }
    }
}
