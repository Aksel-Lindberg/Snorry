import Foundation
import SwiftData
import os.log

// MARK: - SwiftData CRUD for sessions and events
/// All methods must be called on `@MainActor` because they touch the model context.
@MainActor
final class SessionStore {

    private let context: ModelContext
    private let logger = Logger(subsystem: "app.Snorry", category: "SessionStore")

    private var activeSession: SnoreSession?
    private var openEvents: [UUID: SnoreEvent] = [:]

    /// Debounced saves keyed by context so **any** `SessionStore` instance (or Settings bulk-delete)
    /// can cancel pending writes for the shared main `ModelContext`.
    private static var pendingDebouncedSaveTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    // Accumulate stats in memory to avoid frequent SwiftData flushes
    private var waveformAccumulator: [WaveformSample] = []
    private var lastWaveformFlush = Date()

    init(context: ModelContext) {
        self.context = context
    }

    /// Cancels a delayed `save()` scheduled after clip path updates — call before bulk-delete or teardown.
    static func cancelPendingDebouncedSave(for context: ModelContext) {
        let key = ObjectIdentifier(context)
        pendingDebouncedSaveTasks[key]?.cancel()
        pendingDebouncedSaveTasks[key] = nil
    }

    // MARK: Session lifecycle

    func startSession() -> SnoreSession {
        let session = SnoreSession()
        context.insert(session)
        activeSession = session
        UserDefaults.standard.set(session.id.uuidString, forKey: "currentSessionID")
        logger.info("Session started: \(session.id)")
        return session
    }

    func finalizeSession() {
        cancelPendingSave()
        guard let session = activeSession else { return }
        session.endDate = Date()

        rollupStatistics(for: session)

        flushWaveformBuffer(to: session)
        saveContext()

        UserDefaults.standard.removeObject(forKey: "currentSessionID")
        activeSession = nil
        openEvents.removeAll()
        logger.info("Session finalized: \(session.id)")
    }

    /// Recomputes denormalized session fields from `events`, counting only confirmed snoring bouts.
    /// Sleep-talking and environment events are stored in the `events` relationship but excluded
    /// from all snore-statistics fields so the Analytics / History / Home screens stay snoring-centric.
    private func rollupStatistics(for session: SnoreSession) {
        let snoringEvents = session.events.filter { $0.endDate != nil && $0.soundKind == .snoring }
        session.eventCount = snoringEvents.count
        session.totalSnoreDuration = snoringEvents.compactMap { $0.duration }.reduce(0, +)
        let brpms = snoringEvents.filter { $0.brpm > 0 }.map { $0.brpm }
        session.avgBRPM = brpms.isEmpty ? 0 : brpms.reduce(0, +) / Double(brpms.count)
        session.peakDB = snoringEvents.map { $0.peakDB }.max() ?? -160
    }

    // MARK: Event lifecycle

    func beginEvent(id: UUID, at date: Date) {
        guard let session = activeSession else { return }
        let event = SnoreEvent(id: id, startDate: date)
        event.session = session
        session.events.append(event)
        context.insert(event)
        openEvents[id] = event
        logger.debug("Event began: \(id)")
    }

    func endEvent(id: UUID, at date: Date, brpm: Double, peakDB: Float,
                  avgDB: Float, rumbleFrequencyHz: Double) {
        guard let event = openEvents[id] else { return }
        event.endDate = date
        event.brpm = brpm
        event.peakDB = peakDB
        event.avgDB = avgDB
        event.rumbleFrequencyHz = rumbleFrequencyHz
        openEvents.removeValue(forKey: id)
        logger.debug("Event ended: \(id), breathHarmonic=\(rumbleFrequencyHz) Hz, avgDB=\(avgDB)")
    }

    /// Background clip analysis writes the measured rumble peak after `endEvent`.
    func setSpectralPeakHz(_ peakHz: Double, eventID: UUID) {
        let uuid = eventID
        let descriptor = FetchDescriptor<SnoreEvent>(predicate: #Predicate<SnoreEvent> { snoreEvent in
            snoreEvent.id == uuid
        })
        guard let event = try? context.fetch(descriptor).first else {
            logger.warning("setSpectralPeakHz: no event \(eventID.uuidString)")
            return
        }
        event.spectralPeakHz = peakHz
        saveContext()
        logger.debug("Spectral peak stored: \(eventID) \(peakHz) Hz")
    }

    func updateEventAudioPath(_ path: String, eventID: UUID) {
        // Prefer the in-memory map, but fall back to the session relationship — the event
        // may have left `openEvents` while clips are still attributed to its id.
        let event = openEvents[eventID] ?? activeSession?.events.first { $0.id == eventID }
        guard let event else {
            logger.warning("updateEventAudioPath: no event \(eventID.uuidString)")
            return
        }
        event.audioRelativePath = path
        scheduleDebouncedSave()
        logger.debug("Audio path set for event \(eventID.uuidString): \(path)")
    }

    // MARK: Waveform samples (buffered, flushed every 60 s)

    func addWaveformSample(dBFS: Float, brpm: Double, isSnoringActive: Bool) {
        let sample = WaveformSample(timestamp: Date(), dBFS: dBFS,
                                    brpm: brpm, isSnoringActive: isSnoringActive)
        waveformAccumulator.append(sample)

        let now = Date()
        if now.timeIntervalSince(lastWaveformFlush) >= 60 {
            flushWaveformBuffer(to: activeSession)
            lastWaveformFlush = now
        }
    }

    private func flushWaveformBuffer(to session: SnoreSession?) {
        guard let session, !waveformAccumulator.isEmpty else { return }
        cancelPendingSave()
        for sample in waveformAccumulator {
            sample.session = session
            session.waveformSamples.append(sample)
            context.insert(sample)
        }
        waveformAccumulator.removeAll()
        saveContext()
    }

    // MARK: Query

    func fetchSessions() throws -> [SnoreSession] {
        var descriptor = FetchDescriptor<SnoreSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return try context.fetch(descriptor)
    }

    func deleteSession(_ session: SnoreSession) {
        cancelPendingSave()
        // Remove audio clips
        for event in session.events {
            if let url = event.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        context.delete(session)
        saveContext()
    }

    // MARK: Orphan recovery

    /// Call on launch to close any session that was interrupted by a prior process kill.
    func recoverOrphanedSession() {
        guard let idString = UserDefaults.standard.string(forKey: "currentSessionID"),
              let id = UUID(uuidString: idString) else { return }

        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.id == id }
        )
        if let orphan = try? context.fetch(descriptor).first {
            let end = Date()
            orphan.endDate = end
            // Bouts still “open” at crash never got `endEvent` — close them so rollup matches the event log.
            for event in orphan.events where event.endDate == nil {
                event.endDate = end
            }
            rollupStatistics(for: orphan)
            saveContext()
            logger.info("Recovered orphaned session: \(id)")
        }
        UserDefaults.standard.removeObject(forKey: "currentSessionID")
    }

    /// Repairs denormalized stats for sessions saved before orphan rollup existed, or rows where `eventCount` drifted.
    func reconcileEndedSessionsOnLaunch() {
        let descriptor = FetchDescriptor<SnoreSession>()
        guard let sessions = try? context.fetch(descriptor) else { return }
        var anyChanged = false
        for session in sessions {
            guard let sessionEnd = session.endDate else { continue }
            var touched = false
            for event in session.events where event.endDate == nil {
                event.endDate = sessionEnd
                touched = true
            }
            let completed = session.events.filter { $0.endDate != nil }.count
            if touched || completed != session.eventCount {
                rollupStatistics(for: session)
                anyChanged = true
            }
        }
        if anyChanged {
            saveContext()
            logger.info("Reconciled session rollups for ended sessions")
        }
    }

    // MARK: Private

    private func cancelPendingSave() {
        Self.cancelPendingDebouncedSave(for: context)
    }

    /// Batches rapid `audioRelativePath` writes from clip lifecycle into one flush to disk.
    private func scheduleDebouncedSave() {
        let key = ObjectIdentifier(context)
        Self.pendingDebouncedSaveTasks[key]?.cancel()
        Self.pendingDebouncedSaveTasks[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            Self.pendingDebouncedSaveTasks[key] = nil
            self.saveContext()
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            logger.error("SwiftData save failed: \(error)")
        }
    }
}
