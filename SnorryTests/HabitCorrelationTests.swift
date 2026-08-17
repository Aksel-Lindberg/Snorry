import Foundation
import Testing
@testable import Snorry

// MARK: - Habit vs snore duration correlation
struct HabitCorrelationTests {

    private let calendar = Calendar.current

    @Test func computesWithAndWithoutAverages() {
        let dayA = day(0)
        let dayB = day(-1)
        let dayC = day(-2)

        let nights = [
            DailySnorePoint(date: dayA, snoreMinutes: 20, eventCount: 4),
            DailySnorePoint(date: dayB, snoreMinutes: 10, eventCount: 2),
            DailySnorePoint(date: dayC, snoreMinutes: 5, eventCount: 1)
        ]

        let logs = [
            HabitLog(habitID: HabitKind.ateLate.id, dayStart: dayA),
            HabitLog(habitID: HabitKind.ateLate.id, dayStart: dayB)
        ]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: logs,
            exerciseDays: [],
            calendar: calendar
        )

        let ateLate = points.first { $0.id == HabitKind.ateLate.id }
        #expect(ateLate != nil)
        #expect(ateLate?.avgWithHabitMinutes == 15)
        #expect(ateLate?.avgWithoutHabitMinutes == 5)
        #expect(ateLate?.nightsWithHabit == 2)
        #expect(ateLate?.nightsWithoutHabit == 1)
        #expect(ateLate?.deltaMinutes == 10)
    }

    @Test func myofascialUnionsExerciseCompletions() {
        let dayA = day(0)
        let dayB = day(-1)

        let nights = [
            DailySnorePoint(date: dayA, snoreMinutes: 12, eventCount: 2),
            DailySnorePoint(date: dayB, snoreMinutes: 18, eventCount: 3)
        ]

        let exerciseDays: Set<Date> = [dayB]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: [],
            exerciseDays: exerciseDays,
            calendar: calendar
        )

        let exercise = points.first { $0.id == HabitKind.myofascialExercise.id }
        #expect(exercise != nil)
        #expect(exercise?.nightsWithHabit == 1)
        #expect(exercise?.avgWithHabitMinutes == 18)
        #expect(exercise?.avgWithoutHabitMinutes == 12)
    }

    @Test func lowConfidenceWhenFewNightsInBucket() {
        let dayA = day(0)
        let nights = [DailySnorePoint(date: dayA, snoreMinutes: 8, eventCount: 1)]
        let logs = [HabitLog(habitID: HabitKind.congested.id, dayStart: dayA)]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: logs,
            exerciseDays: [],
            calendar: calendar
        )

        let congested = points.first { $0.id == HabitKind.congested.id }
        #expect(congested?.isLowConfidenceWith == true)
        #expect(congested?.isLowConfidenceWithout == true)
    }

    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }
}
