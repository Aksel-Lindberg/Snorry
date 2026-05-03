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
/// Stores the last `capacity` PCM buffers so ClipRecorder can prepend them.
final class PreRollRingBuffer: @unchecked Sendable {

    private var buffers: [AVAudioPCMBuffer]
    private var head = 0
    private let lock = NSLock()
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.buffers = []
        buffers.reserveCapacity(capacity)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if buffers.count < capacity {
            buffers.append(buffer)
        } else {
            buffers[head] = buffer
            head = (head + 1) % capacity
        }
    }

    /// Returns buffers in chronological order (oldest → newest).
    func snapshot() -> [AVAudioPCMBuffer] {
        lock.lock(); defer { lock.unlock() }
        if buffers.count < capacity {
            return Array(buffers)
        }
        let tail = Array(buffers[head...])
        let front = Array(buffers[..<head])
        return tail + front
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

    /// ~3 s pre-roll at 20 ms tap intervals → 150 buffers
    let preRoll = PreRollRingBuffer(capacity: 150)

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

        preRoll.append(converted)

        let db = AudioMath.rmsDBFS(buffer: converted)
        let tick = MonitorTick(dBFS: db, timestamp: Date(), buffer: converted)
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
