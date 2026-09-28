import Foundation
import SwiftData

// MARK: - Bulk sleep-log wipe (off the main actor)
/// SwiftData bulk deletes must not run on a raw `Task.detached` + `ModelContext` — that can stall indefinitely
/// when competing with the main `ModelContext`. `@ModelActor` provides a dedicated serial executor for the store.
@ModelActor
actor SleepLogsDeletionActor {

    /// Deletes the given sessions (cascades events + waveform samples). Returns clip URLs for background file cleanup.
    func deleteSessions(withIDs ids: [UUID]) throws -> [URL] {
        guard !ids.isEmpty else { return [] }

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        var clipURLs: [URL] = []
        clipURLs.reserveCapacity(ids.count * 4)

        for id in ids {
            let sessionID = id
            let descriptor = FetchDescriptor<SnoreSession>(
                predicate: #Predicate<SnoreSession> { $0.id == sessionID }
            )
            guard let session = try modelContext.fetch(descriptor).first else { continue }

            for event in session.events {
                if let rel = event.audioRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !rel.isEmpty {
                    clipURLs.append(support.appendingPathComponent(rel))
                }
            }
            modelContext.delete(session)
        }

        try modelContext.save()
        return clipURLs
    }

    /// Repairs denormalized stats for ended sessions — runs off the main actor so launch stays responsive.
    func reconcileEndedSessionsOnLaunch() throws {
        let sessions = try modelContext.fetch(FetchDescriptor<SnoreSession>())
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
                Self.rollupStatistics(for: session)
                anyChanged = true
            }
        }
        if anyChanged {
            try modelContext.save()
        }
    }

    /// Deletes every `SnoreSession` (cascades events + waveform samples), all `AlertSettingsChange` rows,
    /// all `HabitLog` rows, and all `CustomHabit` rows. Returns resolved clip file URLs for best-effort cleanup after commit.
    func deleteAllSessionsAndSettingsMarkers() throws -> [URL] {
        let events = try modelContext.fetch(FetchDescriptor<SnoreEvent>())
        var clipURLs: [URL] = []
        clipURLs.reserveCapacity(events.count)
        for event in events {
            if let url = event.audioURL {
                clipURLs.append(url)
            }
        }

        try modelContext.delete(model: SnoreSession.self, where: #Predicate { _ in true })
        try modelContext.delete(model: AlertSettingsChange.self, where: #Predicate { _ in true })
        try modelContext.delete(model: HabitLog.self, where: #Predicate { _ in true })
        try modelContext.delete(model: CustomHabit.self, where: #Predicate { _ in true })
        try modelContext.save()
        return clipURLs
    }

    /// Recomputes denormalized session fields from snoring events only.
    private static func rollupStatistics(for session: SnoreSession) {
        let snoringEvents = session.events.filter { $0.endDate != nil && $0.soundKind == .snoring }
        session.eventCount = snoringEvents.count
        session.totalSnoreDuration = snoringEvents.compactMap(\.duration).reduce(0, +)
        session.peakDB = snoringEvents.map(\.peakDB).max() ?? -160
    }
}
