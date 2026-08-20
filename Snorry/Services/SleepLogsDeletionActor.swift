import Foundation
import SwiftData

// MARK: - Bulk sleep-log wipe (off the main actor)
/// SwiftData bulk deletes must not run on a raw `Task.detached` + `ModelContext` — that can stall indefinitely
/// when competing with the main `ModelContext`. `@ModelActor` provides a dedicated serial executor for the store.
@ModelActor
actor SleepLogsDeletionActor {

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
}
