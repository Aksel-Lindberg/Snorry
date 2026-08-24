import Foundation
import SwiftData

// MARK: - Free Insights access for the first 7 completed recording nights
enum InsightsTrialTracker {

    static let freeNightLimit = 7

    private static let maxNightCountKey = "insightsTrialMaxCompletedNights"

    /// Highest completed-night count seen on this install (never decreases when logs are deleted).
    static var persistedMaxCompletedNights: Int {
        UserDefaults.standard.integer(forKey: maxNightCountKey)
    }

    /// Nights left before Insights requires Premium.
    static var remainingFreeInsightsNights: Int {
        max(0, freeNightLimit - persistedMaxCompletedNights)
    }

    /// Whether the user may open Insights without a subscription.
    static func canAccessInsights(hasPremium: Bool, context: ModelContext) -> Bool {
        if hasPremium { return true }
        updateMaxCompletedNights(from: context)
        return persistedMaxCompletedNights < freeNightLimit
    }

    /// Refreshes the persisted max from current SwiftData sessions.
    static func updateMaxCompletedNights(from context: ModelContext) {
        let current = uniqueCompletedNightCount(in: context)
        let updated = max(persistedMaxCompletedNights, current)
        guard updated != persistedMaxCompletedNights else { return }
        UserDefaults.standard.set(updated, forKey: maxNightCountKey)
    }

    /// Unique local calendar nights with at least one completed recording.
    static func uniqueCompletedNightCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.endDate != nil }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let calendar = Calendar.current
        let nights = Set(
            sessions.map { SleepNight.dayStart(for: $0.startDate, calendar: calendar) }
        )
        return nights.count
    }
}
