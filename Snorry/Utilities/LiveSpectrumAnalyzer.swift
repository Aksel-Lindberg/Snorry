import Accelerate
import AVFoundation
import Foundation

// MARK: - Real-time FFT power spectrum (log-spaced bands, improved contrast)
/// 512‑point Hann real FFT (`vDSP_fft_zrip`). Bands are logarithmically spaced from
/// `displayMinHz` to Nyquist so low‑frequency snore energy resolves better than uniform linear bins.
final class LiveSpectrumAnalyzer {

    private let fftLength = 512
    private let log2n: vDSP_Length = 9
    private let bandCount: Int
    private let sampleRate: Double
    private let displayMinHz: Float = 45

    private let fftSetup: FFTSetup?

    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var window: [Float]
    private var magnitudesSquared: [Float]

    init(bandCount: Int = 52, sampleRate: Double = AudioMonitorService.targetSampleRate) {
        self.bandCount = bandCount
        self.sampleRate = sampleRate
        self.windowed = [Float](repeating: 0, count: fftLength)
        self.realp = [Float](repeating: 0, count: fftLength / 2)
        self.imagp = [Float](repeating: 0, count: fftLength / 2)
        self.magnitudesSquared = [Float](repeating: 0, count: fftLength / 2)
        self.window = [Float](repeating: 0, count: fftLength)
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        window.withUnsafeMutableBufferPointer { bp in
            vDSP_hann_window(bp.baseAddress!, UInt(fftLength), Int32(vDSP_HANN_NORM))
        }
    }

    deinit {
        guard let fftSetup else { return }
        vDSP_destroy_fftsetup(fftSetup)
    }

    func bands(fromPCM buffer: AVAudioPCMBuffer) -> [Float] {
        guard let ptr = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return [Float](repeating: 0, count: bandCount)
        }
        guard let fftSetup else {
            return [Float](repeating: 0, count: bandCount)
        }

        let copyCount = min(Int(buffer.frameLength), fftLength)
        windowed = [Float](repeating: 0, count: fftLength)
        _ = windowed.withUnsafeMutableBufferPointer { wp in
            memcpy(wp.baseAddress!, ptr[0], copyCount * MemoryLayout<Float>.size)
        }
        for i in 0 ..< fftLength {
            windowed[i] *= window[i]
        }

        realp = [Float](repeating: 0, count: fftLength / 2)
        imagp = [Float](repeating: 0, count: fftLength / 2)

        magnitudesSquared.withUnsafeMutableBufferPointer { magBuf in
            realp.withUnsafeMutableBufferPointer { rbp in
                imagp.withUnsafeMutableBufferPointer { ibp in
                    var split = DSPSplitComplex(realp: rbp.baseAddress!, imagp: ibp.baseAddress!)
                    windowed.withUnsafeBufferPointer { wp in
                        wp.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                          capacity: fftLength / 2) { cptr in
                            vDSP_ctoz(cptr, 1, &split, 1, vDSP_Length(fftLength / 2))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(fftLength / 2))
                }
            }
        }

        let amps = magnitudesSquared.map { sqrt(max(0, $0)) }

        return Self.mapToLogBands(
            amps: amps,
            bandCount: bandCount,
            fftLength: fftLength,
            sampleRate: sampleRate,
            displayMinHz: displayMinHz
        )
    }

    /// Log-frequency edges; RMS merge within each bin; perceptual gamma + noise floor lift.
    private static func mapToLogBands(
        amps: [Float],
        bandCount: Int,
        fftLength: Int,
        sampleRate: Double,
        displayMinHz: Float
    ) -> [Float] {
        let nyquist = Float(sampleRate / 2)
        let binHz = Float(sampleRate) / Float(fftLength)
        guard binHz > 0, nyquist > displayMinHz else {
            return [Float](repeating: 0, count: bandCount)
        }

        let logLo = log(displayMinHz)
        let logHi = log(nyquist)
        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0 ..< bandCount {
            let u0 = Float(b) / Float(bandCount)
            let u1 = Float(b + 1) / Float(bandCount)
            let f0 = exp(logLo + u0 * (logHi - logLo))
            let f1 = exp(logLo + u1 * (logHi - logLo))

            let iStart = max(1, Int(floor(f0 / binHz)))
            let iEnd = min(amps.count - 1, max(iStart, Int(ceil(f1 / binHz)) - 1))
            guard iStart <= iEnd else { continue }

            var sumSq: Float = 0
            var cnt: Float = 0
            for i in iStart ... iEnd {
                let a = amps[i]
                sumSq += a * a
                cnt += 1
            }
            bands[b] = cnt > 0 ? sqrt(sumSq / cnt) : 0 // RMS merge (smoother than raw max)
        }

        guard let vmax = bands.max(), vmax > 1e-12 else {
            return bands.map { _ in 0 }
        }

        let floorFrac: Float = 0.06
        let floor = vmax * floorFrac
        let inv = 1 / (vmax - floor)

        let gamma: Float = 0.52
        return bands.map {
            let x = max(0, ($0 - floor) * inv)
            let g = powf(min(1, x), gamma)
            return min(1, g)
        }
    }
}
