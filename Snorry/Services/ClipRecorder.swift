import AVFoundation
import Foundation
import os.log

// MARK: - Records per-event AAC clips (pre-roll + live audio)
final class ClipRecorder: @unchecked Sendable {

    private var audioFile: AVAudioFile?
    private var currentRelativePath: String?
    private let logger = Logger(subsystem: "app.Snorry", category: "ClipRecorder")

    // AAC encoder settings — bitrate high enough that replays faithfully match
    // what was captured (16 kbps was too thin for natural snore playback).
    private var aacSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: AudioMonitorService.targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000   // 64 kbps mono — good speech/snore clarity, modest file size
        ]
    }

    // MARK: Lifecycle

    /// Begin a new clip for `eventID` within `sessionID`.
    ///
    /// - Parameters:
    ///   - captureFrom: Only pre-roll entries at or after this timestamp are written.
    ///     Pass the first-onset timestamp so the clip starts from the first real snore
    ///     sound, with a 1-second lead-in for context — not from 36 s of silence.
    ///
    /// Audio is written at the same levels as captured (no extra gain) so replay
    /// matches the original recording; use the device volume for listening level.
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
                try audioFile?.write(from: entry.buffer)
            }
            logger.info("Clip started: \(relativePath) (pre-roll from \(leadIn))")
        } catch {
            logger.error("Could not begin clip: \(error)")
            audioFile = nil
            return nil
        }
        return relativePath
    }

    /// Write a live buffer to the current clip (same levels as input).
    func write(buffer: AVAudioPCMBuffer) {
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
        let path = currentRelativePath
        audioFile = nil
        currentRelativePath = nil
        if let p = path { logger.info("Clip closed: \(p)") }
        return path
    }
}
