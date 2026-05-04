import SoundAnalysis
import AVFoundation
import CoreMedia
import CoreML
import os.log

// MARK: - SoundAnalysis wrapper with 3-of-5 majority-vote smoothing
/// Accepts 16 kHz mono Float32 PCM buffers from `AudioMonitorService`
/// and emits `Bool` frames (true = snoring detected) via an AsyncStream.
final class SnoreClassifier: NSObject, @unchecked Sendable {

    private let analyzer: SNAudioStreamAnalyzer
    private let request: SNClassifySoundRequest
    private let analysisQueue = DispatchQueue(label: "app.Snorry.classifier", qos: .userInitiated)

    private var continuation: AsyncStream<Bool>.Continuation?
    private(set) var stream: AsyncStream<Bool>?

    // Majority-vote window: last 5 classification results
    private var voteWindow: [Bool] = []
    private let voteWindowSize = 5
    private let voteThreshold = 3   // at least 3 "snoring" votes to emit true

    /// Minimum classifier confidence to count a frame as snoring.
    /// Derived from the user-facing sensitivity setting (lower → more sensitive).
    var confidenceThreshold: Float = 0.60

    private let logger = Logger(subsystem: "app.Snorry", category: "Classifier")

    // MARK: Init

    override init() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioMonitorService.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        analyzer = SNAudioStreamAnalyzer(format: format)

        // Built-in classifier — label set includes "snoring".
        // Load the bundled mlmodelc manually with cpuAndGPU compute units to avoid
        // the ANE "InnerProduct kernel has no weights" error on some devices / OS versions.
        request = Self.makeRequest()

        super.init()
    }

    private static func makeRequest() -> SNClassifySoundRequest {
        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .cpuAndGPU

        let modelURL = URL(fileURLWithPath:
            "/System/Library/Frameworks/SoundAnalysis.framework/SNSoundClassifierVersion1Model.mlmodelc")

        if let mlModel = try? MLModel(contentsOf: modelURL, configuration: mlConfig),
           let req = try? SNClassifySoundRequest(mlModel: mlModel) {
            req.windowDuration = CMTime(seconds: 1.0,
                                        preferredTimescale: CMTimeScale(AudioMonitorService.targetSampleRate))
            req.overlapFactor = 0.5
            return req
        }

        // Fallback: let the system choose compute units (may still log an ANE warning,
        // but the classifier will fall back to CPU automatically and continue working).
        let fallback = try! SNClassifySoundRequest(classifierIdentifier: .version1)
        fallback.windowDuration = CMTime(seconds: 1.0,
                                         preferredTimescale: CMTimeScale(AudioMonitorService.targetSampleRate))
        fallback.overlapFactor = 0.5
        return fallback
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
            self?.analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }
}

// MARK: - SNResultsObserving

extension SnoreClassifier: SNResultsObserving {

    func request(_ request: SNRequest,
                 didProduce result: SNResult) {
        guard let classResult = result as? SNClassificationResult else { return }

        // Look for the "snoring" label from the built-in classifier
        let snoringLabel = "snoring"
        let confidence = classResult.classifications
            .first(where: { $0.identifier.lowercased() == snoringLabel })
            .map { $0.confidence } ?? 0

        let isSnoring = Float(confidence) >= confidenceThreshold

        // Majority vote smoothing
        voteWindow.append(isSnoring)
        if voteWindow.count > voteWindowSize {
            voteWindow.removeFirst()
        }
        let votes = voteWindow.filter { $0 }.count
        let smoothed = votes >= voteThreshold

        continuation?.yield(smoothed)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        logger.error("Classifier error: \(error)")
    }
}
