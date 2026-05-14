import AVFoundation
import CoreML
import CoreMedia
import SoundAnalysis
import os.log

// MARK: - Post-stop classification of recorded AAC clips

/// Classifies a saved AAC clip using `SNAudioStreamAnalyzer` (CPU-only) to distinguish
/// snoring from sleep talking and background environment sounds.
///
/// Intended to be called once per session, after monitoring pipelines have stopped,
/// on any night that included a lock/background recording period. On foreground-only
/// nights the RMS gate is conservative enough that no reclassification is needed.
enum SessionClipSoundClassifier {

    private static let logger = Logger(subsystem: "app.Snorry", category: "ClipClassifier")

    // MARK: Tuning

    /// Minimum aggregate snoring score fraction to keep a bout classified as snoring.
    /// Lowered relative to the live threshold so clips with mixed content still count.
    static var snoringMinScore: Float = 0.25

    /// Minimum aggregate speech-like score fraction for sleep-talking classification.
    /// Must exceed `snoringMinScore` to win the tie-break.
    static var sleepTalkingMinScore: Float = 0.35

    /// Apple SoundAnalysis identifiers that are grouped into the "sleep talking" bucket.
    private static let sleepTalkingLabels: Set<String> = [
        "speech",
        "whispering",
        "conversation",
        "narration, monologue",
        "child speech, kid speaking",
        "male speech, man speaking",
        "female speech, woman speaking"
    ]

    // MARK: Public API

    /// Classifies a single clip at `fileURL`.
    ///
    /// - Returns: The inferred `SoundEventKind`. Falls back to `.environment` on analysis
    ///   failure so noise-gate false positives do not inflate snore statistics.
    static func classify(fileURL: URL) async -> SoundEventKind {
        do {
            return try await analyzeClip(at: fileURL)
        } catch {
            logger.warning("Clip classification failed (\(fileURL.lastPathComponent)): \(error.localizedDescription) — marking environment")
            return .environment
        }
    }

    /// Classifies every event in `events` concurrently (up to 3 in parallel).
    /// Writes the result back to `event.soundKind` on the main actor.
    ///
    /// - Parameters:
    ///   - events: Completed `SnoreEvent` rows that were recorded during a background period.
    ///   - applicationSupport: Base URL for resolving `audioRelativePath`.
    ///   - onUpdate: Called on `@MainActor` after each event is classified so the stop
    ///     overlay can show progress if desired.
    @MainActor
    static func classifyAll(
        events: [SnoreEvent],
        applicationSupport: URL,
        onUpdate: ((SnoreEvent, SoundEventKind) -> Void)? = nil
    ) async {
        // Capture id + relative path + current kind so we don't hold live model objects
        // across actor hops.
        let work: [(id: UUID, url: URL?, kind: SoundEventKind)] = events.map { event in
            let url: URL? = event.audioRelativePath.flatMap { rel in
                let u = applicationSupport.appendingPathComponent(rel)
                return FileManager.default.fileExists(atPath: u.path) ? u : nil
            }
            return (event.id, url, event.soundKind)
        }

        // Run up to 3 files concurrently; more would starve the UI thread and CPU budget.
        await withTaskGroup(of: (UUID, SoundEventKind).self) { group in
            var inFlight = 0
            var pending = work.makeIterator()

            func enqueue() {
                while inFlight < 3, let item = pending.next() {
                    inFlight += 1
                    let (id, url, _) = item
                    group.addTask {
                        guard let url else {
                            // No saved clip → treat as environment noise
                            return (id, .environment)
                        }
                        let kind = await classify(fileURL: url)
                        return (id, kind)
                    }
                }
            }

            enqueue()

            for await (id, kind) in group {
                inFlight -= 1
                // Write result back on MainActor (SwiftData models are main-actor owned)
                if let event = events.first(where: { $0.id == id }) {
                    event.soundKind = kind
                    onUpdate?(event, kind)
                }
                enqueue()
            }
        }
    }

    // MARK: Private — single-file analysis

    private static func analyzeClip(at url: URL) async throws -> SoundEventKind {
        // Decode + resample to 16 kHz mono (matches live pipeline)
        let samples = try decodeTo16kMono(url: url)
        guard !samples.isEmpty else { return .environment }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        let request = makeRequest()
        let analyzer = SNAudioStreamAnalyzer(format: format)

        let observer = AccumulatingObserver()
        try analyzer.add(request, withObserver: observer)
        defer { analyzer.remove(request) }

        // Feed in 0.5 s chunks so SoundAnalysis has enough context per window
        let chunkFrames = Int(format.sampleRate * 0.5)
        let frameCount  = samples.count

        var offset = 0
        var sampleTime: Int64 = 0

        while offset < frameCount {
            let available = frameCount - offset
            let thisChunk = min(chunkFrames, available)

            guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(thisChunk)) else { break }
            buf.frameLength = AVAudioFrameCount(thisChunk)
            let dst = buf.floatChannelData![0]
            samples.withUnsafeBufferPointer { src in
                dst.initialize(from: src.baseAddress! + offset, count: thisChunk)
            }

            let time = AVAudioTime(sampleTime: sampleTime, atRate: format.sampleRate)
            analyzer.analyze(buf, atAudioFramePosition: time.sampleTime)

            offset    += thisChunk
            sampleTime += Int64(thisChunk)
        }

        analyzer.completeAnalysis()

        return observer.decision(
            snoringMin: snoringMinScore,
            sleepTalkingMin: sleepTalkingMinScore,
            sleepTalkingLabels: sleepTalkingLabels
        )
    }

    // MARK: Private — request factory (CPU-only, mirrors SnoreClassifier)

    private static func makeRequest() -> SNClassifySoundRequest {
        let window = CMTime(seconds: 1.0,
                            preferredTimescale: CMTimeScale(16_000))

        func configure(_ req: SNClassifySoundRequest) {
            req.windowDuration = window
            req.overlapFactor  = 0.5
        }

        let modelPath =
            "/System/Library/Frameworks/SoundAnalysis.framework/SNSoundClassifierVersion1Model.mlmodelc"

        if FileManager.default.fileExists(atPath: modelPath) {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuOnly
            if let mlModel = try? MLModel(contentsOf: URL(fileURLWithPath: modelPath),
                                          configuration: cfg),
               let req = try? SNClassifySoundRequest(mlModel: mlModel) {
                configure(req)
                return req
            }
        }

        // Simulator / device without system model on disk
        if let req = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            configure(req)
            return req
        }

        fatalError("SessionClipSoundClassifier: could not create SNClassifySoundRequest")
    }

    // MARK: Private — PCM decode + resample

    /// Reads an AVAudioFile, mixes to mono, resamples to 16 kHz Float32.
    private static func decodeTo16kMono(url: URL) throws -> [Float] {
        let file   = try AVAudioFile(forReading: url)
        let srcFmt = file.processingFormat
        let count  = AVAudioFrameCount(file.length)
        guard count > 0 else { return [] }

        guard let src = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: count) else { return [] }
        try file.read(into: src)

        let targetFmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        // If already at the right format, just mix to mono in-place
        if srcFmt.sampleRate == 16_000, srcFmt.commonFormat == .pcmFormatFloat32 {
            return mixToMono(src)
        }

        // Use AVAudioConverter for everything else
        guard let converter = AVAudioConverter(from: srcFmt, to: targetFmt) else { return [] }

        let outCount = AVAudioFrameCount(
            Double(count) * (targetFmt.sampleRate / srcFmt.sampleRate) + 1
        )
        guard let dst = AVAudioPCMBuffer(pcmFormat: targetFmt, frameCapacity: outCount) else { return [] }

        var inputConsumed = false
        let status = converter.convert(to: dst, error: nil) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return src
        }

        guard status != .error, dst.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: dst.floatChannelData![0],
                                         count: Int(dst.frameLength)))
    }

    private static func mixToMono(_ buf: AVAudioPCMBuffer) -> [Float] {
        guard let data = buf.floatChannelData else { return [] }
        let frames   = Int(buf.frameLength)
        let channels = Int(buf.format.channelCount)
        guard channels > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for ch in 0..<channels {
            let src = data[ch]
            for i in 0..<frames { mono[i] += src[i] }
        }
        if channels > 1 {
            let inv = 1.0 / Float(channels)
            for i in 0..<frames { mono[i] *= inv }
        }
        return mono
    }
}

// MARK: - Accumulating SoundAnalysis observer

/// Collects per-window confidence scores across all analysis frames and
/// computes a final `SoundEventKind` from the aggregated evidence.
private final class AccumulatingObserver: NSObject, SNResultsObserving {

    // Sum of per-window confidences for each label
    private var scores: [String: Double] = [:]
    private var windowCount = 0

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        windowCount += 1
        for c in r.classifications {
            scores[c.identifier, default: 0] += c.confidence
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        // individual window failures are tolerated; the aggregate will still decide
    }

    /// Converts accumulated scores into the best `SoundEventKind`.
    func decision(
        snoringMin: Float,
        sleepTalkingMin: Float,
        sleepTalkingLabels: Set<String>
    ) -> SoundEventKind {
        guard windowCount > 0 else { return .environment }

        let n = Double(windowCount)
        let snoringScore   = Float(scores["snoring", default: 0] / n)
        let talkingScore   = Float(sleepTalkingLabels.reduce(0.0) { $0 + scores[$1, default: 0] } / n)

        // Sleep talking wins only if it clearly exceeds snoring and crosses its own threshold.
        if talkingScore >= sleepTalkingMin, talkingScore > snoringScore {
            return .sleepTalking
        }
        if snoringScore >= snoringMin {
            return .snoring
        }
        return .environment
    }
}
