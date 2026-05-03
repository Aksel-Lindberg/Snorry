import AVFoundation
import Foundation
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
    /// Immediately writes the pre-roll buffers from the ring buffer.
    func beginClip(sessionID: UUID, eventID: UUID,
                   preRoll: PreRollRingBuffer) -> String? {
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

            // Write pre-roll (oldest → newest)
            for buffer in preRoll.snapshot() {
                try audioFile?.write(from: buffer)
            }
            logger.info("Clip started: \(relativePath)")
        } catch {
            logger.error("Could not begin clip: \(error)")
            audioFile = nil
            return nil
        }
        return relativePath
    }

    /// Write a live buffer to the current clip.
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
