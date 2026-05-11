import AVFoundation
import Foundation
import os.log

// MARK: - Records per-event AAC clips (pre-roll + live audio)
final class ClipRecorder: @unchecked Sendable {

    /// Serializes access — clip begin/end runs on MainActor while PCM writes run on the monitoring pipeline queue.
    private let ioLock = NSLock()
    private var audioFile: AVAudioFile?
    private var currentRelativePath: String?
    private let logger = Logger(subsystem: "app.Snorry", category: "ClipRecorder")

    // MARK: AAC encoder settings

    /// Builds encoder settings matched to the native hardware input format so that
    /// replayed clips sound exactly like the original recording — full sample-rate
    /// and original channel count, no amplitude adjustment.
    private func aacSettings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            // 128 kbps gives excellent snore clarity at 44.1/48 kHz;
            // it stays modest in file size (≈1 MB/min for mono, ≈2 MB/min for stereo).
            AVEncoderBitRateKey: 128_000
        ]
    }

    // MARK: Lifecycle

    /// Begin a new clip for `eventID` within `sessionID`.
    ///
    /// - Parameters:
    ///   - nativePreRoll: Ring buffer holding native-format (full sample-rate) PCM buffers.
    ///   - inputFormat:   The native hardware `AVAudioFormat` — determines the AAC output rate
    ///                    and channel count so replay volume matches what was recorded.
    ///   - captureFrom:   Only pre-roll entries at or after this timestamp are written.
    ///     Pass the first-onset timestamp so the clip starts from the first real snore
    ///     sound, with a 1-second lead-in for context.
    func beginClip(sessionID: UUID, eventID: UUID,
                   nativePreRoll: PreRollRingBuffer,
                   inputFormat: AVAudioFormat,
                   captureFrom: Date) -> String? {
        ioLock.lock()
        defer { ioLock.unlock() }

        endClipUnderLock()   // safety: close any open file

        let relativePath = "SnoreClips/\(sessionID.uuidString)/\(eventID.uuidString).m4a"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileURL = support.appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // AVAudioFile handles PCM→AAC internally; commonFormat must match the
            // buffers we write (AVAudioEngine taps are always Float32 non-interleaved).
            audioFile = try AVAudioFile(forWriting: fileURL,
                                        settings: aacSettings(for: inputFormat),
                                        commonFormat: .pcmFormatFloat32,
                                        interleaved: false)
            currentRelativePath = relativePath

            // Write pre-roll starting 1 s before the first onset for context.
            let leadIn = captureFrom.addingTimeInterval(-1.0)
            for entry in nativePreRoll.snapshot(from: leadIn) {
                try audioFile?.write(from: entry.buffer)
            }
            logger.info("""
                Clip started: \(relativePath) \
                (\(inputFormat.sampleRate, privacy: .public) Hz, \
                \(inputFormat.channelCount, privacy: .public) ch, \
                pre-roll from \(leadIn))
                """)
        } catch {
            logger.error("Could not begin clip: \(error)")
            audioFile = nil
            return nil
        }
        return relativePath
    }

    /// Write a live native-format buffer to the current clip (same levels as input).
    func write(buffer: AVAudioPCMBuffer) {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard let file = audioFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            logger.error("Clip write error: \(error)")
        }
    }

    /// Close the current clip.
    @discardableResult
    func endClip() -> String? {
        ioLock.lock()
        defer { ioLock.unlock() }
        return endClipUnderLock()
    }

    private func endClipUnderLock() -> String? {
        let path = currentRelativePath
        audioFile = nil
        currentRelativePath = nil
        if let closedPath = path { logger.info("Clip closed: \(closedPath)") }
        return path
    }
}
