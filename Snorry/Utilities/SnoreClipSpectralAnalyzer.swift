import AVFoundation
import Foundation
import Accelerate

/// Estimates the dominant frequency of a recorded snore clip using an FFT.
enum SnoreClipSpectralAnalyzer {

    /// Loads an audio file, converts to mono float samples, and returns the dominant spectral peak in Hz.
    nonisolated static func dominantPeakHz(fileURL: URL) throws -> Double? {
        let file = try AVAudioFile(forReading: fileURL)
        let processingFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
            return nil
        }
        try file.read(into: buffer)

        let sampleRate = processingFormat.sampleRate
        let channelCount = Int(processingFormat.channelCount)
        guard channelCount > 0 else { return nil }

        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // Mix down to mono so peak detection behaves consistently.
        var mono = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let src = channelData[channel]
            vDSP_vadd(mono, 1, src, 1, &mono, 1, vDSP_Length(frameLength))
        }

        var divisor = Float(channelCount)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(frameLength))

        return peakHz(monoSamples: mono, sampleRate: sampleRate)
    }

    /// Returns the dominant peak frequency in the provided mono signal.
    nonisolated static func peakHz(monoSamples: [Float], sampleRate: Double) -> Double? {
        guard sampleRate > 0 else { return nil }

        // Use a power-of-two FFT window for efficient, stable spectral estimation.
        let maxWindowSize = 4096
        let usableCount = min(monoSamples.count, maxWindowSize)
        guard usableCount >= 512 else { return nil }

        let log2n = vDSP_Length(log2(Float(usableCount)))
        let fftSize = 1 << Int(log2n)
        guard fftSize >= 512 else { return nil }

        var windowed = Array(monoSamples.prefix(fftSize))
        guard windowed.count == fftSize else { return nil }

        // Remove DC bias first so very low-frequency energy does not dominate the spectrum.
        var mean: Float = 0
        vDSP_meanv(windowed, 1, &mean, vDSP_Length(fftSize))
        var negMean = -mean
        vDSP_vsadd(windowed, 1, &negMean, &windowed, 1, vDSP_Length(fftSize))

        var hann = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hann, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(windowed, 1, hann, 1, &windowed, 1, vDSP_Length(fftSize))

        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD) else {
            return nil
        }
        defer { vDSP_DFT_DestroySetup(setup) }

        var imagInput = [Float](repeating: 0, count: fftSize)
        var realOutput = [Float](repeating: 0, count: fftSize)
        var imagOutput = [Float](repeating: 0, count: fftSize)

        windowed.withUnsafeMutableBufferPointer { realIn in
            imagInput.withUnsafeMutableBufferPointer { imagIn in
                realOutput.withUnsafeMutableBufferPointer { realOut in
                    imagOutput.withUnsafeMutableBufferPointer { imagOut in
                        vDSP_DFT_Execute(
                            setup,
                            realIn.baseAddress!,
                            imagIn.baseAddress!,
                            realOut.baseAddress!,
                            imagOut.baseAddress!
                        )
                    }
                }
            }
        }

        let halfCount = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfCount)
        for binOffset in 0..<halfCount {
            magnitudes[binOffset] = hypot(realOutput[binOffset], imagOutput[binOffset])
        }

        // Skip bin 0 (DC), then find strongest peak.
        guard halfCount > 2 else { return nil }
        let searchSlice = magnitudes[1..<halfCount]
        guard let maxValue = searchSlice.max(), maxValue > 0 else { return nil }
        guard let relativeIndex = searchSlice.firstIndex(of: maxValue) else { return nil }

        let binIndex = relativeIndex
        let frequencyResolution = sampleRate / Double(fftSize)
        return Double(binIndex) * frequencyResolution
    }
}
