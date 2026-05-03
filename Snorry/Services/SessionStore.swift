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

    // Accumulate stats in memory to avoid frequent SwiftData flushes
    private var waveformAccumulator: [WaveformSample] = []
    private var lastWaveformFlush = Date()

    init(context: ModelContext) {
        self.context = context
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
        guard let session = activeSession else { return }
        session.endDate = Date()

        // Rollup stats
        let completedEvents = session.events.filter { $0.endDate != nil }
        session.eventCount = completedEvents.count
        session.totalSnoreDuration = completedEvents.compactMap { $0.duration }.reduce(0, +)
        let brpms = completedEvents.filter { $0.brpm > 0 }.map { $0.brpm }
        session.avgBRPM = brpms.isEmpty ? 0 : brpms.reduce(0, +) / Double(brpms.count)
        session.peakDB = completedEvents.map { $0.peakDB }.max() ?? -160

        flushWaveformBuffer(to: session)
        saveContext()

        UserDefaults.standard.removeObject(forKey: "currentSessionID")
        activeSession = nil
        openEvents.removeAll()
        logger.info("Session finalized: \(session.id)")
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

    func endEvent(id: UUID, at date: Date, brpm: Double, peakDB: Float) {
        guard let event = openEvents[id] else { return }
        event.endDate = date
        event.brpm = brpm
        event.peakDB = peakDB
        openEvents.removeValue(forKey: id)
        logger.debug("Event ended: \(id)")
    }

    func updateEventAudioPath(_ path: String, eventID: UUID) {
        guard let event = openEvents[eventID] else { return }
        event.audioRelativePath = path
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

    /// Call on launch to close any session that was interrupted by a process kill.
    func recoverOrphanedSession() {
        guard let idString = UserDefaults.standard.string(forKey: "currentSessionID"),
              let id = UUID(uuidString: idString) else { return }

        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.id == id }
        )
        if let orphan = try? context.fetch(descriptor).first {
            orphan.endDate = Date()
            saveContext()
            logger.info("Recovered orphaned session: \(id)")
        }
        UserDefaults.standard.removeObject(forKey: "currentSessionID")
    }

    // MARK: Private

    private func saveContext() {
        do {
            try context.save()
        } catch {
            logger.error("SwiftData save failed: \(error)")
        }
    }
}
