import Foundation
import SwiftData
import Testing
@testable import Snorry

// MARK: - Insights trial (7 completed recording nights)
struct InsightsTrialTrackerTests {

    private let maxNightCountKey = "insightsTrialMaxCompletedNights"

    @Test func accessAllowedBeforeSevenNights() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: maxNightCountKey)

        insertCompletedSession(on: day(0), in: context)
        insertCompletedSession(on: day(-1), in: context)
        try context.save()

        #expect(InsightsTrialTracker.canAccessInsights(hasPremium: false, context: context))
        #expect(InsightsTrialTracker.persistedMaxCompletedNights == 2)
    }

    @Test func accessBlockedAfterSevenNights() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: maxNightCountKey)

        for offset in 0..<7 {
            insertCompletedSession(on: day(-offset), in: context)
        }
        try context.save()

        #expect(!InsightsTrialTracker.canAccessInsights(hasPremium: false, context: context))
        #expect(InsightsTrialTracker.persistedMaxCompletedNights == 7)
    }

    @Test func persistedMaxSurvivesSessionDeletion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: maxNightCountKey)

        for offset in 0..<7 {
            insertCompletedSession(on: day(-offset), in: context)
        }
        try context.save()
        InsightsTrialTracker.updateMaxCompletedNights(from: context)
        #expect(InsightsTrialTracker.persistedMaxCompletedNights == 7)

        try context.delete(model: SnoreSession.self, where: #Predicate { _ in true })
        try context.save()

        #expect(InsightsTrialTracker.uniqueCompletedNightCount(in: context) == 0)
        #expect(!InsightsTrialTracker.canAccessInsights(hasPremium: false, context: context))
        #expect(InsightsTrialTracker.persistedMaxCompletedNights == 7)
    }

    @Test func premiumAlwaysHasAccess() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: maxNightCountKey)

        for offset in 0..<10 {
            insertCompletedSession(on: day(-offset), in: context)
        }
        try context.save()

        #expect(InsightsTrialTracker.canAccessInsights(hasPremium: true, context: context))
    }

    @Test func twoSessionsSameSleepNightCountAsOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: maxNightCountKey)

        insertCompletedSession(on: dayWithTime(offsetDays: 0, hour: 22), in: context)
        insertCompletedSession(on: dayWithTime(offsetDays: 0, hour: 23), in: context)
        try context.save()

        #expect(InsightsTrialTracker.uniqueCompletedNightCount(in: context) == 1)
    }

    @Test func afterMidnightAndEveningSameCalendarDateCountAsTwoNights() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        UserDefaults.standard.removeObject(forKey: maxNightCountKey)

        insertCompletedSession(on: dayWithTime(offsetDays: 0, hour: 0, minute: 52), in: context)
        insertCompletedSession(on: dayWithTime(offsetDays: 0, hour: 23, minute: 11), in: context)
        try context.save()

        #expect(InsightsTrialTracker.uniqueCompletedNightCount(in: context) == 2)
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SnoreSession.self, SnoreEvent.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ offset: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func dayWithTime(offsetDays: Int, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = day(offsetDays)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func insertCompletedSession(on start: Date, in context: ModelContext) {
        let session = SnoreSession(startDate: start)
        session.endDate = start.addingTimeInterval(6 * 3600)
        session.totalSnoreDuration = 600
        session.eventCount = 3
        context.insert(session)
    }
}
