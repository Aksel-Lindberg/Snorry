import AVFoundation
import Accelerate
import os.log

// MARK: - A frame of live audio data published each tap callback (~20 ms)
struct MonitorTick: Sendable {
    let dBFS: Float
    let timestamp: Date
    /// Reference to the buffer for waveform display (short-lived).
    let buffer: AVAudioPCMBuffer
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

    /// 36 s pre-roll (1800 buffers × 20 ms) — covers the full BRPM confirmation window.
    let preRoll = PreRollRingBuffer()

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
        logger.info("AudioMonitorService started")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        stream = nil
        AudioSessionManager.shared.deactivate()
        logger.info("AudioMonitorService stopped")
    }

    // MARK: Buffer processing

    private func process(buffer: AVAudioPCMBuffer) {
        guard let conv = converter,
              let converted = convert(buffer: buffer, using: conv) else { return }

        let now = Date()
        preRoll.append(converted, at: now)

        let db = AudioMath.rmsDBFS(buffer: converted)
        let tick = MonitorTick(dBFS: db, timestamp: now, buffer: converted)
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
