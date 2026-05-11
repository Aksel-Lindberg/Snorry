import AVFoundation
import Accelerate
import os.log

// MARK: - A frame of live audio data published each tap callback (~20 ms)
struct MonitorTick: Sendable {
    let dBFS: Float
    let timestamp: Date
    /// 16 kHz mono Float32 buffer — for the classifier and waveform display.
    let buffer: AVAudioPCMBuffer
    /// Native device-format buffer (e.g. 48 kHz stereo Float32) — for clip recording
    /// so replayed clips match the original sound, not the downsampled analysis path.
    let nativeBuffer: AVAudioPCMBuffer
}

// MARK: - Pre-roll circular ring buffer (thread-safe)
/// Stores the last `capacity` PCM buffers with timestamps so ClipRecorder can
/// write only the audio that starts at (or just before) a given point in time.
final class PreRollRingBuffer: @unchecked Sendable {

    struct Entry: Sendable {
        let timestamp: Date
        let buffer: AVAudioPCMBuffer
    }

    private var entries: [Entry]
    private var head = 0
    private let lock = NSLock()
    let capacity: Int

    /// 1800 buffers × 20 ms = 36 s — enough to cover the slowest BRPM confirmation
    /// window (4 onsets × 8 s each = 32 s) with room to spare.
    init(capacity: Int = 1800) {
        self.capacity = capacity
        self.entries = []
        entries.reserveCapacity(capacity)
    }

    func append(_ buffer: AVAudioPCMBuffer, at timestamp: Date) {
        lock.lock(); defer { lock.unlock() }
        let entry = Entry(timestamp: timestamp, buffer: buffer)
        if entries.count < capacity {
            entries.append(entry)
        } else {
            entries[head] = entry
            head = (head + 1) % capacity
        }
    }

    /// Returns entries in chronological order (oldest → newest),
    /// optionally filtered to those with timestamp ≥ `from`.
    func snapshot(from startDate: Date? = nil) -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        let ordered: [Entry]
        if entries.count < capacity {
            ordered = Array(entries)
        } else {
            ordered = Array(entries[head...]) + Array(entries[..<head])
        }
        guard let from = startDate else { return ordered }
        return ordered.filter { $0.timestamp >= from }
    }
}

// MARK: - Core audio engine + microphone tap
/// Owns `AVAudioEngine`, converts tap output to 16 kHz mono Float32,
/// measures RMS, feeds the pre-roll ring buffer, and vends an AsyncStream.
final class AudioMonitorService: @unchecked Sendable {

    static let shared = AudioMonitorService()

    // Target format for classifier + RMS
    static let targetSampleRate: Double = 16_000
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    /// 36 s pre-roll of 16 kHz mono buffers — fed to `ClipRecorder` for analysis-aligned clips.
    let preRoll = PreRollRingBuffer()

    /// 36 s pre-roll of native-format buffers — fed to `ClipRecorder` so clips replay at full quality.
    let nativePreRoll = PreRollRingBuffer()

    /// Native hardware input format (set when `start()` is called).
    private(set) var inputFormat: AVAudioFormat?

    private var continuation: AsyncStream<MonitorTick>.Continuation?
    private(set) var stream: AsyncStream<MonitorTick>?

    private let logger = Logger(subsystem: "app.Snorry", category: "AudioMonitor")

    private init() {}

    // MARK: Start / Stop

    func start() throws {
        guard stream == nil else { return }

        try AudioSessionManager.shared.configureForMonitoring()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        self.inputFormat = inputFormat

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        let (asyncStream, cont) = AsyncStream<MonitorTick>.makeStream()
        self.stream = asyncStream
        self.continuation = cont

        // ~20 ms tap at native sample rate
        let tapFrames = AVAudioFrameCount(inputFormat.sampleRate * 0.02)

        inputNode.installTap(onBus: 0, bufferSize: tapFrames, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        AudioSessionManager.shared.setMonitoringAudioActive(true)
        logger.info("AudioMonitorService started")
    }

    /// After phone calls, Siri, or other session interruptions, re-activates the session and restarts
    /// the engine if monitoring is still supposed to be running (`stream` remains non-nil).
    func resumeAfterInterruptionIfNeeded() {
        guard stream != nil else { return }
        do {
            try AudioSessionManager.shared.configureForMonitoring()
            if !engine.isRunning {
                try engine.start()
            }
            logger.info("AudioMonitorService resumed after interruption")
        } catch {
            logger.error("Failed to resume AudioMonitorService after interruption: \(error)")
        }
    }

    func stop() {
        AudioSessionManager.shared.setMonitoringAudioActive(false)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        stream = nil
        inputFormat = nil
        AudioSessionManager.shared.deactivate()
        logger.info("AudioMonitorService stopped")
    }

    // MARK: Buffer processing

    private func process(buffer: AVAudioPCMBuffer) {
        let now = Date()
        // Store the native-format buffer first so it's available for full-quality clip recording.
        nativePreRoll.append(buffer, at: now)

        guard let conv = converter,
              let converted = convert(buffer: buffer, using: conv) else { return }

        preRoll.append(converted, at: now)

        let db = AudioMath.rmsDBFS(buffer: converted)
        let tick = MonitorTick(dBFS: db, timestamp: now, buffer: converted, nativeBuffer: buffer)
        continuation?.yield(tick)
    }

    private func convert(buffer: AVAudioPCMBuffer,
                         using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                            frameCapacity: targetFrames) else { return nil }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        return output
    }
}
