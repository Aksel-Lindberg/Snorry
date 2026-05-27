import Accelerate
import AVFoundation
import Foundation

// MARK: - Live spectral gate for snore rumble vs. plain breathing

/// Scores low-frequency rumble energy (85–400 Hz) against mid/high reference (400–2000 Hz)
/// using a 512-point Hann FFT — same sample rate as the classifier path (16 kHz mono).
enum SnoreRumbleGate {

    struct Config: Sendable {
        /// Rumble-band RMS must exceed reference-band RMS by this factor.
        var ratioThreshold: Float = 1.15
        /// Minimum overall signal RMS in dBFS before evaluating the ratio.
        var minSignalDBFS: Float = -58
        /// Reject when speech-band (300–3400 Hz) RMS exceeds rumble RMS by this factor (sleep talking).
        /// Set to 0 to disable.
        var speechDominanceRejectionRatio: Float = 1.35
    }

    private static let fftLength = 512
    private static let log2n: vDSP_Length = 9
    private static let rumbleLowHz: Float = 85
    private static let rumbleHighHz: Float = 400
    private static let referenceLowHz: Float = 400
    private static let referenceHighHz: Float = 2000
    private static let speechLowHz: Float = 300
    private static let speechHighHz: Float = 3400

    /// Returns `true` when the buffer carries dominant low-frequency rumble characteristic of snoring.
    static func passes(buffer: AVAudioPCMBuffer, config: Config = Config()) -> Bool {
        guard let ptr = buffer.floatChannelData, buffer.frameLength > 0 else { return false }
        return passes(
            samples: ptr[0],
            count: Int(buffer.frameLength),
            sampleRate: Float(buffer.format.sampleRate),
            config: config
        )
    }

    /// Testable entry point for synthetic sine buffers.
    static func passes(
        samples: UnsafePointer<Float>,
        count: Int,
        sampleRate: Float,
        config: Config = Config()
    ) -> Bool {
        guard count > 0, sampleRate > 0 else { return false }

        var windowed = [Float](repeating: 0, count: fftLength)
        let copyCount = min(count, fftLength)
        windowed.withUnsafeMutableBufferPointer { wp in
            memcpy(wp.baseAddress!, samples, copyCount * MemoryLayout<Float>.size)
        }
        return analyzeWindowed(windowed, sampleRate: sampleRate, config: config)
    }

    /// Evaluates a full 512-sample window (used by ``SnoreRumbleTracker``).
    static func passesWindow(_ window: [Float], sampleRate: Float, config: Config = Config()) -> Bool {
        guard window.count == fftLength, sampleRate > 0 else { return false }
        return analyzeWindowed(window, sampleRate: sampleRate, config: config)
    }

    private static func analyzeWindowed(
        _ windowed: [Float],
        sampleRate: Float,
        config: Config
    ) -> Bool {
        var signalRMS: Float = 0
        vDSP_measqv(windowed, 1, &signalRMS, vDSP_Length(fftLength))
        signalRMS = sqrt(max(0, signalRMS))
        guard signalRMS > 1e-12 else { return false }

        let signalDB = 20 * log10(signalRMS)
        guard signalDB >= config.minSignalDBFS else { return false }

        var hannWindow = [Float](repeating: 0, count: fftLength)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftLength), Int32(vDSP_HANN_NORM))

        var weighted = windowed
        vDSP_vmul(weighted, 1, hannWindow, 1, &weighted, 1, vDSP_Length(fftLength))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return false }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realp = [Float](repeating: 0, count: fftLength / 2)
        var imagp = [Float](repeating: 0, count: fftLength / 2)
        var magnitudesSquared = [Float](repeating: 0, count: fftLength / 2)

        realp.withUnsafeMutableBufferPointer { rbp in
            imagp.withUnsafeMutableBufferPointer { ibp in
                magnitudesSquared.withUnsafeMutableBufferPointer { magBuf in
                    var split = DSPSplitComplex(realp: rbp.baseAddress!, imagp: ibp.baseAddress!)
                    weighted.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftLength / 2) { cptr in
                            vDSP_ctoz(cptr, 1, &split, 1, vDSP_Length(fftLength / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(fftLength / 2))
                }
            }
        }

        let amps = magnitudesSquared.map { sqrt(max(0, $0)) }
        let binHz = sampleRate / Float(fftLength)

        let rumbleRMS = bandRMS(amps: amps, binHz: binHz, lowHz: rumbleLowHz, highHz: rumbleHighHz)
        let refRMS = bandRMS(amps: amps, binHz: binHz, lowHz: referenceLowHz, highHz: referenceHighHz)

        guard rumbleRMS > 1e-12 else { return false }

        if config.speechDominanceRejectionRatio > 0 {
            let speechRMS = bandRMS(amps: amps, binHz: binHz, lowHz: speechLowHz, highHz: speechHighHz)
            if speechRMS / rumbleRMS >= config.speechDominanceRejectionRatio {
                return false
            }
        }

        let refSafe = max(refRMS, 1e-12)
        return (rumbleRMS / refSafe) >= config.ratioThreshold
    }

    private static func bandRMS(amps: [Float], binHz: Float, lowHz: Float, highHz: Float) -> Float {
        let iStart = max(1, Int(floor(lowHz / binHz)))
        let iEnd = min(amps.count - 1, max(iStart, Int(ceil(highHz / binHz)) - 1))
        guard iStart <= iEnd else { return 0 }

        var sumSq: Float = 0
        var cnt: Float = 0
        for binIndex in iStart ... iEnd {
            let amp = amps[binIndex]
            sumSq += amp * amp
            cnt += 1
        }
        return cnt > 0 ? sqrt(sumSq / cnt) : 0
    }
}

// MARK: - Rolling 512-sample window for stable live rumble detection

/// Accumulates PCM into a 512-sample ring so the FFT always has enough context.
/// Thread-safe for use on the classifier analysis queue only.
final class SnoreRumbleTracker: @unchecked Sendable {

    private let fftLength = 512
    private var ring = [Float](repeating: 0, count: 512)
    private var writeIndex = 0
    private var sampleCount = 0
    var config = SnoreRumbleGate.Config()
    /// When true (lock screen), applies stricter rumble + speech rejection before counting a frame.
    var useBackgroundStrictMode = false

    /// Ingests a PCM buffer and returns whether the current 512-sample window passes the rumble gate.
    func feed(buffer: AVAudioPCMBuffer, sampleRate: Float) -> Bool {
        guard let ptr = buffer.floatChannelData, buffer.frameLength > 0 else { return false }
        let count = Int(buffer.frameLength)
        for offset in 0 ..< count {
            ring[writeIndex] = ptr[0][offset]
            writeIndex = (writeIndex + 1) % fftLength
            sampleCount = min(sampleCount + 1, fftLength)
        }
        guard sampleCount == fftLength else { return false }

        // Read ring in chronological order for FFT input.
        var ordered = [Float](repeating: 0, count: fftLength)
        for idx in 0 ..< fftLength {
            ordered[idx] = ring[(writeIndex + idx) % fftLength]
        }
        return SnoreRumbleGate.passesWindow(ordered, sampleRate: sampleRate, config: effectiveConfig())
    }

    private func effectiveConfig() -> SnoreRumbleGate.Config {
        guard useBackgroundStrictMode else { return config }
        var cfg = config
        cfg.ratioThreshold += 0.12
        cfg.speechDominanceRejectionRatio = max(cfg.speechDominanceRejectionRatio, 1.45)
        return cfg
    }
}
