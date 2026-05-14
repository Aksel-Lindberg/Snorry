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

    private var continuation: AsyncStream<Bool>.Continuation?
    private(set) var stream: AsyncStream<Bool>?

    // Majority-vote window: last 5 classification results
    private var voteWindow: [Bool] = []
    private let voteWindowSize = 5
    /// Foreground SoundAnalysis path — 3-of-5 votes.
    private let foregroundVoteThreshold = 3
    /// Background RMS path — stricter (less sensitive): need 4-of-5 loud frames.
    private let energyFallbackVoteThreshold = 4

    /// Minimum classifier confidence to count a frame as snoring.
    /// Derived from the user-facing sensitivity setting (lower → more sensitive).
    var confidenceThreshold: Float = 0.60

    /// Background RMS gate: higher dBFS = louder required → **less** sensitive than foreground ML.
    /// Adjusted with the user’s snore sensitivity setting together with `confidenceThreshold`.
    var energyFallbackThresholdDB: Float = -42

    /// Only read/written on `analysisQueue` — true after `didEnterBackground`, false after `willEnterForeground`.
    private var useEnergyFallbackWhileBackground = false

    private let logger = Logger(subsystem: "app.Snorry", category: "Classifier")

    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

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
        backgroundObserver = nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { [weak self] in
                guard let self else { return }
                self.useEnergyFallbackWhileBackground = true
                self.voteWindow.removeAll()
                self.logger.info("Classifier: lock/background — RMS energy gate (SoundAnalysis paused, no GPU)")
            }
        }
        foregroundObserver = nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { [weak self] in
                guard let self else { return }
                self.useEnergyFallbackWhileBackground = false
                self.voteWindow.removeAll()
                self.logger.info("Classifier: foreground — SoundAnalysis active again")
            }
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
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
        // On device we prefer loading the compiled model with `.cpuOnly` (see comment above); this
        // initializer may allow GPU/ANE and is avoided there when the system model file exists.
        do {
            let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
            applyWindowing(req)
            return req
        } catch {
            fatalError("SnoreClassifier: could not create SNClassifySoundRequest(.version1): \(error)")
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
        logger.info("SnoreClassifier stopped")
    }

    // MARK: Feed buffers

    func analyze(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        analysisQueue.async { [weak self] in
            guard let self else { return }

            if self.useEnergyFallbackWhileBackground {
                let db = AudioMath.rmsDBFS(buffer: buffer)
                let loud = db >= self.energyFallbackThresholdDB
                self.pushVoteFrame(loud)
                return
            }

            self.analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
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
            // Ignore late SoundAnalysis callbacks while we are in energy-only mode (no GPU submitted).
            guard !self.useEnergyFallbackWhileBackground else { return }

            let snoringLabel = "snoring"
            let confidence = classResult.classifications
                .first(where: { $0.identifier.lowercased() == snoringLabel })
                .map { $0.confidence } ?? 0

            let isSnoring = Float(confidence) >= self.confidenceThreshold
            self.pushVoteFrame(isSnoring)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Classifier error: \(error)")
    }
}

// MARK: - Snore sensitivity → classifier + onset detector

/// Maps the Settings slider (1…5) to foreground ML thresholds and the lock-screen RMS gate.
/// Level **3** matches the historical fixed tuning (confidence 0.30, onset +2 dB, RMS −42 dBFS).
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
        detector.onsetThresholdDB = profile.onsetThresholdDB
    }

    private struct Profile {
        let confidenceThreshold: Float
        let onsetThresholdDB: Float
        let energyFallbackThresholdDB: Float
    }

    private static func profile(for level: Int) -> Profile {
        switch level {
        case 1:
            return Profile(confidenceThreshold: 0.75, onsetThresholdDB: 20, energyFallbackThresholdDB: -28)
        case 2:
            // Blend 0.5 of the historical low ↔ high curve (matches interpolated onset/confidence).
            return Profile(confidenceThreshold: 0.525, onsetThresholdDB: 11, energyFallbackThresholdDB: -35)
        case 3:
            return Profile(confidenceThreshold: 0.30, onsetThresholdDB: 2, energyFallbackThresholdDB: -42)
        case 4:
            return Profile(confidenceThreshold: 0.22, onsetThresholdDB: 1.25, energyFallbackThresholdDB: -44)
        case 5:
            return Profile(confidenceThreshold: 0.15, onsetThresholdDB: 0.75, energyFallbackThresholdDB: -46)
        default:
            return profile(for: 3)
        }
    }
}
