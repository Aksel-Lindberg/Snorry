import AVFoundation
import Foundation
import Accelerate
import os.log

// MARK: - Records per-event AAC clips (pre-roll + live audio)
final class ClipRecorder: @unchecked Sendable {

    private var audioFile: AVAudioFile?
    private var currentRelativePath: String?
    private let logger = Logger(subsystem: "app.Snorry", category: "ClipRecorder")

    private let writeFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioMonitorService.targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Gain applied to every written buffer so recordings are loud at playback.
    /// ×4 = +12 dB. Microphone input in .measurement mode typically arrives at
    /// −30 to −20 dBFS; boosting brings it to −18 to −8 dBFS (clearly audible).
    private let recordingGain: Float = 4.0

    // AAC encoder settings for the output file
    private var aacSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioMonitorService.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 16_000   // 16 kbps mono
        ]
    }

    // MARK: Lifecycle

    /// Begin a new clip for `eventID` within `sessionID`.
    ///
    /// - Parameters:
    ///   - captureFrom: Only pre-roll entries at or after this timestamp are written.
    ///     Pass the first-onset timestamp so the clip starts from the first real snore
    ///     sound, with a 1-second lead-in for context — not from 36 s of silence.
    func beginClip(sessionID: UUID, eventID: UUID,
                   preRoll: PreRollRingBuffer,
                   captureFrom: Date) -> String? {
        endClip()   // safety: close any open file

        let relativePath = "SnoreClips/\(sessionID.uuidString)/\(eventID.uuidString).m4a"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileURL = support.appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            audioFile = try AVAudioFile(forWriting: fileURL,
                                        settings: aacSettings,
                                        commonFormat: .pcmFormatFloat32,
                                        interleaved: false)
            currentRelativePath = relativePath

            // Write pre-roll starting 1 s before the first onset for context.
            let leadIn = captureFrom.addingTimeInterval(-1.0)
            for entry in preRoll.snapshot(from: leadIn) {
                try audioFile?.write(from: amplified(entry.buffer))
            }
            logger.info("Clip started: \(relativePath) (pre-roll from \(leadIn))")
        } catch {
            logger.error("Could not begin clip: \(error)")
            audioFile = nil
            return nil
        }
        return relativePath
    }

    /// Write a live buffer to the current clip (gain-boosted).
    func write(buffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }
        do {
            try file.write(from: amplified(buffer))
        } catch {
            logger.error("Clip write error: \(error)")
        }
    }

    // MARK: Gain helper

    /// Returns a new PCM buffer with every sample multiplied by `recordingGain`
    /// and hard-limited to [−1, 1] to prevent clipping distortion.
    private func amplified(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let frameCount = Int(source.frameLength)
        guard frameCount > 0,
              let src = source.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: source.format,
                                        frameCapacity: source.frameCapacity)
        else { return source }

        out.frameLength = source.frameLength
        guard let dst = out.floatChannelData else { return source }

        var gain = recordingGain
        // Multiply samples by gain.
        vDSP_vsmul(src[0], 1, &gain, dst[0], 1, vDSP_Length(frameCount))
        // Hard-limit: clamp to [−1, 1].
        var lo: Float = -1.0, hi: Float = 1.0
        vDSP_vclip(dst[0], 1, &lo, &hi, dst[0], 1, vDSP_Length(frameCount))
        return out
    }

    /// Close the current clip.
    @discardableResult
    func endClip() -> String? {
        let path = currentRelativePath
        audioFile = nil
        currentRelativePath = nil
        if let p = path { logger.info("Clip closed: \(p)") }
        return path
    }
}
