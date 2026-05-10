import Accelerate
import AVFoundation
import Foundation

// MARK: - Offline spectral peak from a recorded snore clip (AAC / PCM via AVAudioFile)

/// Finds a **measured** dominant frequency in the snore “rumble” band from the saved event clip.
/// Unlike the breath‑tempo harmonic (BRPM‑derived), this reflects actual spectral energy in the recording
/// and varies more with airway shape / timbre — closer to what you’d use to compare different people.
enum SnoreClipSpectralAnalyzer {

    private static let fftLength = 4096
    private static let log2n: vDSP_Length = 12
    private static let hop = 2048
    /// Typical snore body / rumble; avoids very low coupling and high harmonics noise.
    private static let bandMinHz: Double = 80
    private static let bandMaxHz: Double = 1200
    private static let maxAnalyzeSeconds: Double = 20

    /// Dominant frequency (Hz) from time‑averaged magnitude spectrum, or `nil` if unreadable / no energy.
    static func dominantPeakHz(fileURL: URL) throws -> Double? {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let sr = format.sampleRate
        guard sr > 0, fftLength >= 64 else { return nil }

        let chCount = Int(format.channelCount)
        guard chCount > 0 else { return nil }

        // Stream decode: AAC `file.length` is often 0 until fully parsed — one-shot read then yields no samples.
        let maxSamples = min(Int(maxAnalyzeSeconds * sr), 1_200_000)
        var mono: [Float] = []
        mono.reserveCapacity(min(maxSamples, 480_000))

        let chunkCap: AVAudioFrameCount = 8192
        while mono.count < maxSamples {
            let want = min(Int(chunkCap), maxSamples - mono.count)
            guard want > 0,
                  let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(want)) else { break }
            do {
                try file.read(into: buf, frameCount: AVAudioFrameCount(want))
            } catch {
                break
            }
            let n = Int(buf.frameLength)
            if n == 0 { break }
            guard let ch = buf.floatChannelData else { break }

            if chCount == 1 {
                mono.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
            } else {
                var slice = [Float](repeating: 0, count: n)
                slice.withUnsafeMutableBufferPointer { dst in
                    memcpy(dst.baseAddress!, ch[0], n * MemoryLayout<Float>.size)
                }
                for c in 1..<chCount {
                    vDSP_vadd(slice, 1, ch[c], 1, &slice, 1, vDSP_Length(n))
                }
                var inv = 1 / Float(chCount)
                vDSP_vsmul(slice, 1, &inv, &slice, 1, vDSP_Length(n))
                mono.append(contentsOf: slice)
            }
        }

        guard mono.count >= 256 else { return nil }
        return peakHz(monoSamples: mono, sampleRate: sr)
    }

    /// Core FFT / peak-bin search — exposed for tests (synthetic sine, etc.).
    static func peakHz(monoSamples: [Float], sampleRate: Double) -> Double? {
        let n = fftLength
        let sr = sampleRate
        guard !monoSamples.isEmpty, sr > 0,
              let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        window.withUnsafeMutableBufferPointer { bp in
            vDSP_hann_window(bp.baseAddress!, UInt(n), Int32(vDSP_HANN_NORM))
        }

        var accum = [Float](repeating: 0, count: n / 2)
        var windows = 0

        var readPos = 0
        while readPos + n <= monoSamples.count {
            var windowed = [Float](repeating: 0, count: n)
            monoSamples.withUnsafeBufferPointer { src in
                memcpy(windowed.withUnsafeMutableBytes { $0.baseAddress! },
                       src.baseAddress!.advanced(by: readPos),
                       n * MemoryLayout<Float>.size)
            }
            vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(n))

            var realp = [Float](repeating: 0, count: n / 2)
            var imagp = [Float](repeating: 0, count: n / 2)
            var magsq = [Float](repeating: 0, count: n / 2)

            magsq.withUnsafeMutableBufferPointer { magBuf in
                realp.withUnsafeMutableBufferPointer { rbp in
                    imagp.withUnsafeMutableBufferPointer { ibp in
                        var split = DSPSplitComplex(realp: rbp.baseAddress!, imagp: ibp.baseAddress!)
                        windowed.withUnsafeBufferPointer { wp in
                            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cptr in
                                vDSP_ctoz(cptr, 1, &split, 1, vDSP_Length(n / 2))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(n / 2))
                    }
                }
            }

            var mag = magsq.map { sqrt(max(0, $0)) }
            vDSP_vadd(accum, 1, mag, 1, &accum, 1, vDSP_Length(n / 2))
            windows += 1
            readPos += hop
        }

        // Single short clip: one zero-padded frame from the start.
        if windows == 0, monoSamples.count >= 64 {
            var windowed = [Float](repeating: 0, count: n)
            let copy = min(monoSamples.count, n)
            monoSamples.withUnsafeBufferPointer { src in
                memcpy(windowed.withUnsafeMutableBytes { $0.baseAddress! },
                       src.baseAddress!,
                       copy * MemoryLayout<Float>.size)
            }
            for i in copy..<n { windowed[i] = 0 }
            vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(n))

            var realp = [Float](repeating: 0, count: n / 2)
            var imagp = [Float](repeating: 0, count: n / 2)
            var magsq = [Float](repeating: 0, count: n / 2)
            magsq.withUnsafeMutableBufferPointer { magBuf in
                realp.withUnsafeMutableBufferPointer { rbp in
                    imagp.withUnsafeMutableBufferPointer { ibp in
                        var split = DSPSplitComplex(realp: rbp.baseAddress!, imagp: ibp.baseAddress!)
                        windowed.withUnsafeBufferPointer { wp in
                            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cptr in
                                vDSP_ctoz(cptr, 1, &split, 1, vDSP_Length(n / 2))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(n / 2))
                    }
                }
            }
            accum = magsq.map { sqrt(max(0, $0)) }
            windows = 1
        }

        guard windows > 0 else { return nil }
        vDSP_vsdiv(accum, 1, [Float(windows)], &accum, 1, vDSP_Length(n / 2))

        let minBin = max(1, Int(floor(bandMinHz * Double(n) / sr)))
        let maxBin = min(n / 2 - 1, Int(ceil(bandMaxHz * Double(n) / sr)))
        guard minBin <= maxBin else { return nil }

        var peakIdx = minBin
        var peakVal = accum[minBin]
        for i in (minBin + 1)...maxBin {
            if accum[i] > peakVal {
                peakVal = accum[i]
                peakIdx = i
            }
        }

        // Noise floor: ignore if average in band is tiny.
        var bandMean: Float = 0
        accum.withUnsafeBufferPointer { ap in
            vDSP_meanv(ap.baseAddress!.advanced(by: minBin), 1, &bandMean, vDSP_Length(maxBin - minBin + 1))
        }
        guard peakVal > max(1e-9, bandMean * 3.5) else { return nil }

        return Double(peakIdx) * sr / Double(n)
    }
}
