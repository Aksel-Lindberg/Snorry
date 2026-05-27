import SoundAnalysis
import AVFoundation
import CoreMedia
import CoreML
import UIKit
import os.log

// MARK: - SoundAnalysis wrapper with 3-of-5 majority-vote smoothing
/// Accepts 16 kHz mono Float32 PCM buffers from `AudioMonitorService`
/// and emits `Bool` frames (true = snoring detected) via an AsyncStream.
///
/// **Background / lock screen:** iOS forbids GPU (Metal) work while the app is backgrounded, even with
/// background audio. SoundAnalysis’s bundled pipeline still touches Espresso/Metal internally, so when
/// the device locks we **stop calling** `SNAudioStreamAnalyzer` and use a coarse RMS-level gate instead.
/// That avoids `kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted` entirely.
final class SnoreClassifier: NSObject, @unchecked Sendable {

    private let analyzer: SNAudioStreamAnalyzer
    private let request: SNClassifySoundRequest
    private let analysisQueue = DispatchQueue(label: "app.Snorry.classifier", qos: .userInitiated)
    private let rumbleTracker = SnoreRumbleTracker()

    private var continuation: AsyncStream<Bool>.Continuation?
    private(set) var stream: AsyncStream<Bool>?

    // Majority-vote window: last 5 classification results
    private var voteWindow: [Bool] = []
    private var rumbleVoteWindow: [Bool] = []
    private let voteWindowSize = 5
    /// Foreground SoundAnalysis path — 3-of-5 votes.
    private let foregroundVoteThreshold = 3
    /// Background RMS path — stricter (less sensitive): need 4-of-5 loud frames.
    private let energyFallbackVoteThreshold = 4
    /// Lock-screen rumble vote — 3-of-5 rejects quiet broadband environment noise.
    private let backgroundRumbleVoteThreshold = 3
    /// Rumble vote threshold — 2-of-5 keeps sensitivity while still rejecting steady breathing.
    private let rumbleVoteThreshold = 2

    /// Minimum classifier confidence to count a frame as snoring.
    /// Set from ``SnoreDetectionTuning`` using the saved sensitivity level (app default: maximum).
    var confidenceThreshold: Float = 0.60

    /// Background RMS gate: higher dBFS = louder required → **less** sensitive than foreground ML.
    /// Set from ``SnoreDetectionTuning`` together with `confidenceThreshold`.
    var energyFallbackThresholdDB: Float = -42
    /// Lock-screen floor — rejects low-volume environment hum even when sensitivity is high.
    var backgroundMinimumLevelDB: Float = -38

    /// Reject only when breathing confidence clearly exceeds snoring (foreground ML path).
    var breathingRejectionMargin: Float = 0.05

    /// Spectral rumble tuning applied to the rolling 512-sample tracker.
    var rumbleConfig: SnoreRumbleGate.Config {
        get { rumbleTracker.config }
        set { rumbleTracker.config = newValue }
    }

    /// Only read/written on `analysisQueue` — true after `didEnterBackground`, false after `willEnterForeground`.
    private var useEnergyFallbackWhileBackground = false

    private let logger = Logger(subsystem: "app.Snorry", category: "Classifier")

    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var resignedActiveObserver: NSObjectProtocol?

    // MARK: Init

    override init() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioMonitorService.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        analyzer = SNAudioStreamAnalyzer(format: format)

        // CPU-only Core ML load — used while foreground; still avoids the identifier fallback that may pick GPU.
        request = Self.makeRequest()

        super.init()

        let queue = analysisQueue
        let nc = NotificationCenter.default

        func enterLockScreenPath() {
            queue.async { [weak self] in
                guard let self else { return }
                self.useEnergyFallbackWhileBackground = true
                self.rumbleTracker.useBackgroundStrictMode = true
                self.voteWindow.removeAll()
                self.rumbleVoteWindow.removeAll()
                self.logger.info("Classifier: lock/background — RMS energy gate (SoundAnalysis paused, no GPU)")
            }
        }

        func leaveLockScreenPath() {
            queue.async { [weak self] in
                guard let self else { return }
                self.useEnergyFallbackWhileBackground = false
                self.rumbleTracker.useBackgroundStrictMode = false
                self.voteWindow.removeAll()
                self.rumbleVoteWindow.removeAll()
                self.logger.info("Classifier: foreground — SoundAnalysis active again")
            }
        }

        backgroundObserver = nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard self != nil else { return }
            enterLockScreenPath()
        }
        foregroundObserver = nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard self != nil else { return }
            leaveLockScreenPath()
        }
        resignedActiveObserver = nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard self != nil else { return }
            enterLockScreenPath()
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let resignedActiveObserver {
            NotificationCenter.default.removeObserver(resignedActiveObserver)
        }
    }

    private static func makeRequest() -> SNClassifySoundRequest {
        let windowDuration = CMTime(
            seconds: 1.0,
            preferredTimescale: CMTimeScale(AudioMonitorService.targetSampleRate)
        )
        let overlapFactor = 0.5

        func applyWindowing(_ req: SNClassifySoundRequest) {
            req.windowDuration = windowDuration
            req.overlapFactor = overlapFactor
        }

        // On device, load the framework’s compiled model with CPU-only to avoid Metal while foreground
        // (background path still avoids calling the analyzer). The Simulator does not ship this file.
        let modelPath =
            "/System/Library/Frameworks/SoundAnalysis.framework/SNSoundClassifierVersion1Model.mlmodelc"

        if FileManager.default.fileExists(atPath: modelPath) {
            let mlConfig = MLModelConfiguration()
            mlConfig.computeUnits = .cpuOnly
            let modelURL = URL(fileURLWithPath: modelPath)
            do {
                let mlModel = try MLModel(contentsOf: modelURL, configuration: mlConfig)
                let req = try SNClassifySoundRequest(mlModel: mlModel)
                applyWindowing(req)
                return req
            } catch {
                fatalError("SnoreClassifier: system SoundAnalysis model failed to load (CPU): \(error)")
            }
        }

        // Simulator (and any host missing the on-disk `.mlmodelc`): use Apple’s identifier API.
        do {
            let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
            applyWindowing(req)
            return req
        } catch {
            fatalError("SnoreClassifier: could not create SNClassifySoundRequest(.version1): \(error)")
        }
    }

    /// Mirrors UIApplication lock/background state from ``MonitorViewModel`` (covers monitoring start while locked).
    func setLockScreenEnergyMode(_ enabled: Bool) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            guard self.useEnergyFallbackWhileBackground != enabled else { return }
            self.useEnergyFallbackWhileBackground = enabled
            self.rumbleTracker.useBackgroundStrictMode = enabled
            self.voteWindow.removeAll()
            self.rumbleVoteWindow.removeAll()
        }
    }

    // MARK: Lifecycle

    func start() {
        let (s, c) = AsyncStream<Bool>.makeStream()
        stream = s
        continuation = c

        try? analyzer.add(request, withObserver: self)
        logger.info("SnoreClassifier started")
    }

    func stop() {
        analyzer.remove(request)
        continuation?.finish()
        continuation = nil
        stream = nil
        voteWindow.removeAll()
        rumbleVoteWindow.removeAll()
        logger.info("SnoreClassifier stopped")
    }

    // MARK: Feed buffers

    func analyze(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        analysisQueue.async { [weak self] in
            guard let self else { return }

            let rumblePass = self.rumbleTracker.feed(
                buffer: buffer,
                sampleRate: Float(AudioMonitorService.targetSampleRate)
            )
            self.pushRumbleVote(rumblePass)

            if self.useEnergyFallbackWhileBackground {
                let db = AudioMath.rmsDBFS(buffer: buffer)
                let threshold = max(self.energyFallbackThresholdDB, self.backgroundMinimumLevelDB)
                let loud = db >= threshold
                self.pushVoteFrame(loud && self.rumbleRecentlyPassed)
                return
            }

            self.analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }

    private var rumbleRecentlyPassed: Bool {
        guard !rumbleVoteWindow.isEmpty else { return false }
        let need = useEnergyFallbackWhileBackground ? backgroundRumbleVoteThreshold : rumbleVoteThreshold
        return rumbleVoteWindow.filter { $0 }.count >= need
    }

    private func pushRumbleVote(_ pass: Bool) {
        rumbleVoteWindow.append(pass)
        if rumbleVoteWindow.count > voteWindowSize {
            rumbleVoteWindow.removeFirst()
        }
    }

    /// Single exit point for smoothed bool stream (SoundAnalysis + energy paths).
    private func pushVoteFrame(_ rawSnoringFrame: Bool) {
        voteWindow.append(rawSnoringFrame)
        if voteWindow.count > voteWindowSize {
            voteWindow.removeFirst()
        }
        let votes = voteWindow.filter { $0 }.count
        let need = useEnergyFallbackWhileBackground ? energyFallbackVoteThreshold : foregroundVoteThreshold
        let smoothed = votes >= need
        continuation?.yield(smoothed)
    }
}

// MARK: - SNResultsObserving

extension SnoreClassifier: SNResultsObserving {

    func request(_ request: SNRequest,
                 didProduce result: SNResult) {
        guard let classResult = result as? SNClassificationResult else { return }

        analysisQueue.async { [weak self] in
            guard let self else { return }
            guard !self.useEnergyFallbackWhileBackground else { return }

            let snoringConfidence = classResult.classifications
                .first(where: { $0.identifier.lowercased() == "snoring" })
                .map { Float($0.confidence) } ?? 0
            let breathingConfidence = classResult.classifications
                .first(where: { $0.identifier.lowercased() == "breathing" })
                .map { Float($0.confidence) } ?? 0

            // Reject only when breathing clearly dominates — snoring often co-scores with breathing.
            let breathingDominates = breathingConfidence > snoringConfidence + self.breathingRejectionMargin
            let mlPass = snoringConfidence >= self.confidenceThreshold && !breathingDominates
            let isSnoring = mlPass && self.rumbleRecentlyPassed
            self.pushVoteFrame(isSnoring)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Classifier error: \(error)")
    }
}

// MARK: - Snore sensitivity → classifier + onset detector

/// Maps stored snore sensitivity (1…5) to foreground ML thresholds and the lock-screen RMS gate.
enum SnoreDetectionTuning {

    static func apply(
        sensitivityLevel: Double,
        classifier: SnoreClassifier,
        detector: SnoreEventDetector
    ) {
        let level = max(1, min(5, Int(sensitivityLevel.rounded())))
        let profile = profile(for: level)
        classifier.confidenceThreshold = profile.confidenceThreshold
        classifier.energyFallbackThresholdDB = profile.energyFallbackThresholdDB
        classifier.breathingRejectionMargin = profile.breathingRejectionMargin
        classifier.rumbleConfig = profile.rumbleConfig
        detector.onsetThresholdDB = profile.onsetThresholdDB
    }

    private struct Profile {
        let confidenceThreshold: Float
        let onsetThresholdDB: Float
        let energyFallbackThresholdDB: Float
        let rumbleConfig: SnoreRumbleGate.Config
        let breathingRejectionMargin: Float
    }

    private static func profile(for level: Int) -> Profile {
        switch level {
        case 1:
            return Profile(
                confidenceThreshold: 0.75,
                onsetThresholdDB: 20,
                energyFallbackThresholdDB: -28,
                rumbleConfig: SnoreRumbleGate.Config(ratioThreshold: 1.5, minSignalDBFS: -45),
                breathingRejectionMargin: 0.12
            )
        case 2:
            return Profile(
                confidenceThreshold: 0.525,
                onsetThresholdDB: 11,
                energyFallbackThresholdDB: -35,
                rumbleConfig: SnoreRumbleGate.Config(ratioThreshold: 1.3, minSignalDBFS: -50),
                breathingRejectionMargin: 0.08
            )
        case 3:
            return Profile(
                confidenceThreshold: 0.30,
                onsetThresholdDB: 2,
                energyFallbackThresholdDB: -42,
                rumbleConfig: SnoreRumbleGate.Config(ratioThreshold: 1.2, minSignalDBFS: -55),
                breathingRejectionMargin: 0.06
            )
        case 4:
            return Profile(
                confidenceThreshold: 0.22,
                onsetThresholdDB: 1.25,
                energyFallbackThresholdDB: -44,
                rumbleConfig: SnoreRumbleGate.Config(ratioThreshold: 1.15, minSignalDBFS: -57),
                breathingRejectionMargin: 0.05
            )
        case 5:
            return Profile(
                confidenceThreshold: 0.15,
                onsetThresholdDB: 0.75,
                energyFallbackThresholdDB: -46,
                rumbleConfig: SnoreRumbleGate.Config(ratioThreshold: 1.1, minSignalDBFS: -58),
                breathingRejectionMargin: 0.04
            )
        default:
            return profile(for: 3)
        }
    }
}
