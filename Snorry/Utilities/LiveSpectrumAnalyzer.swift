import Accelerate
import AVFoundation
import Foundation

// MARK: - Real-time FFT power spectrum
/// 512-point packed real FFT (`vDSP_fft_zrip`), Hann window, linear frequency bands
/// from near-DC to Nyquist, magnitudes normalised 0…1 for display.
final class LiveSpectrumAnalyzer {

    private let fftLength = 512
    private let log2n: vDSP_Length = 9
    private let bandCount: Int
    private let sampleRate: Double

    private let fftSetup: FFTSetup?

    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var window: [Float]
    private var magnitudesSquared: [Float]

    init(bandCount: Int = 56, sampleRate: Double = AudioMonitorService.targetSampleRate) {
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
        windowed.withUnsafeMutableBufferPointer { wp in
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

        return Self.mapToBands(
            amps: amps,
            bandCount: bandCount,
            fftLength: fftLength,
            sampleRate: sampleRate
        )
    }

    private static func mapToBands(
        amps: [Float],
        bandCount: Int,
        fftLength: Int,
        sampleRate: Double
    ) -> [Float] {
        let nyquist = Float(sampleRate / 2)
        let binHz = Float(sampleRate) / Float(fftLength)
        guard binHz > 0 else {
            return [Float](repeating: 0, count: bandCount)
        }

        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0 ..< bandCount {
            let f0 = nyquist * (Float(b) / Float(bandCount))
            let f1 = nyquist * (Float(b + 1) / Float(bandCount))
            let iStart = max(1, Int(floor(f0 / binHz)))
            let iEnd = min(amps.count - 1, Int(ceil(f1 / binHz)) - 1)
            if iStart <= iEnd {
                var peak: Float = 0
                for i in iStart ... iEnd {
                    peak = max(peak, amps[i])
                }
                bands[b] = peak
            }
        }

        guard let vmax = bands.max(), vmax > 1e-8 else {
            return bands
        }
        let scale = 1 / vmax
        return bands.map { min(1, $0 * scale) }
    }
}
