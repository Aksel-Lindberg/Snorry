import Foundation
import AVFoundation
import SwiftData
import os.log

// MARK: - Chart-only timeline samples (downsampled for Swift Charts performance)

/// Lightweight point for session replay chart — not a persisted `@Model`.
struct TimelineChartPoint: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let dBFS: Float
    let brpm: Double
    let isSnoringActive: Bool
}

private struct WaveformSnapshot: Sendable {
    let id: UUID
    let timestamp: Date
    let dBFS: Float
    let brpm: Double
    let isSnoringActive: Bool
}

@Observable
@MainActor
final class SessionDetailViewModel {

    let session: SnoreSession

    /// Downsampled waveform — avoids rendering tens of thousands of `AreaMark`s.
    private(set) var chartTimelinePoints: [TimelineChartPoint] = []
    private(set) var snoreEvents: [SnoreEvent] = []

    // Playback state
    var playingEventID: UUID?
    /// Surfaces decode / session errors in the UI so replay failures are never silent.
    var playbackDiagnostic: String?

    /// Peak-normalising player: decodes AAC → Float32, boosts gain, plays via AVAudioEngine.
    private let clipPlayer = NormalizingClipPlayer()
    private let logger     = Logger(subsystem: "app.Snorry", category: "SessionDetail")

    /// Loads relationships eagerly off the navigation transition so the History list stays responsive.
    static func prepare(session: SnoreSession, modelContext: ModelContext) async -> SessionDetailViewModel {
        await Task.yield()
        let vm = SessionDetailViewModel(session: session)
        await vm.buildTimeline(from: modelContext)
        return vm
    }

    private init(session: SnoreSession) {
        self.session = session
        snoreEvents = session.events
            .filter { $0.endDate != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    private func buildTimeline(from context: ModelContext) async {
        let sortedSamples = Self.loadSortedWaveformSamples(for: session.id, context: context)
        let snapshots: [WaveformSnapshot] = sortedSamples.map {
            WaveformSnapshot(
                id: $0.id,
                timestamp: $0.timestamp,
                dBFS: $0.dBFS,
                brpm: $0.brpm,
                isSnoringActive: $0.isSnoringActive
            )
        }
        chartTimelinePoints = await Self.downsampleForChart(snapshots)
    }

    private static func loadSortedWaveformSamples(for sessionID: UUID, context: ModelContext) -> [WaveformSample] {
        let byRelationship: () -> [WaveformSample] = {
            var d = FetchDescriptor<SnoreSession>(predicate: #Predicate<SnoreSession> { $0.id == sessionID })
            d.fetchLimit = 1
            guard let s = try? context.fetch(d).first else { return [] }
            return s.waveformSamples.sorted { $0.timestamp < $1.timestamp }
        }

        let descriptor = FetchDescriptor<WaveformSample>(
            predicate: #Predicate<WaveformSample> { sample in
                sample.session?.id == sessionID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        if let fetched = try? context.fetch(descriptor), !fetched.isEmpty {
            return fetched
        }
        return byRelationship()
    }

    /// Caps chart complexity (~2k marks) while preserving coverage across long nights.
    private static func downsampleForChart(_ snapshots: [WaveformSnapshot]) async -> [TimelineChartPoint] {
        let maxPoints = 2000
        guard snapshots.count > maxPoints else {
            return snapshots.map {
                TimelineChartPoint(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    dBFS: $0.dBFS,
                    brpm: $0.brpm,
                    isSnoringActive: $0.isSnoringActive
                )
            }
        }
        return await Task.detached {
            let count = snapshots.count
            var out: [TimelineChartPoint] = []
            out.reserveCapacity(maxPoints)
            let denom = Double(maxPoints - 1)
            for i in 0..<maxPoints {
                let idx = min(count - 1, Int((Double(i) / denom * Double(count - 1)).rounded()))
                let t = snapshots[idx]
                out.append(
                    TimelineChartPoint(
                        id: t.id,
                        timestamp: t.timestamp,
                        dBFS: t.dBFS,
                        brpm: t.brpm,
                        isSnoringActive: t.isSnoringActive
                    )
                )
            }
            return out
        }.value
    }

    // MARK: Playback

    func togglePlayback(of event: SnoreEvent) {
        if playingEventID == event.id {
            stopPlayback()
            return
        }

        guard let url = event.playbackURL else {
            playbackDiagnostic = event.audioRelativePath != nil
                ? "Recorded file missing on disk."
                : "No audio path stored for this event."
            logger.warning("Replay skipped — path=\(String(describing: event.audioRelativePath))")
            return
        }

        stopPlaybackInternal(deactivateSession: false)

        // Wire finish callback before play() so it's set even if play() throws.
        clipPlayer.onFinish = { [weak self] in
            Task { @MainActor in self?.playbackDidFinish() }
        }

        do {
            // Force loudspeaker and reset monitoring's 16 kHz preferred sample rate.
            try AudioSessionManager.shared.configureForClipReplay()
            // Decode, peak-normalise (up to +18 dB), then start AVAudioEngine playback.
            try clipPlayer.play(url: url)
            playingEventID = event.id
            playbackDiagnostic = nil
        } catch {
            logger.error("Replay failed: \(error.localizedDescription)")
            playbackDiagnostic = error.localizedDescription
            playbackDidFinish()
        }
    }

    func stopPlayback() {
        stopPlaybackInternal(deactivateSession: true)
    }

    private func playbackDidFinish() {
        clipPlayer.stop()
        playingEventID = nil
        // Restore automatic output routing and deactivate the replay session.
        AudioSessionManager.shared.resetReplayOverrides()
    }

    private func stopPlaybackInternal(deactivateSession: Bool) {
        clipPlayer.stop()
        playingEventID = nil
        if deactivateSession {
            AudioSessionManager.shared.resetReplayOverrides()
        }
    }

    // MARK: Summary helpers

    var durationString: String { session.displayDurationSummary }
}
