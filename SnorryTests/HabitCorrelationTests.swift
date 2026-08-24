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
        #expect(ateLate?.expectedEffect == .mayAddSnoring)
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
        #expect(exercise?.expectedEffect == .mayHelp)
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

    @Test func includesCustomHabitCorrelation() {
        let dayA = day(0)
        let dayB = day(-1)
        let custom = CustomHabit(title: "Mouth tape")

        let nights = [
            DailySnorePoint(date: dayA, snoreMinutes: 14, eventCount: 2),
            DailySnorePoint(date: dayB, snoreMinutes: 6, eventCount: 1)
        ]

        let logs = [HabitLog(habitID: custom.logID, dayStart: dayA)]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: logs,
            exerciseDays: [],
            customHabits: [custom],
            calendar: calendar
        )

        let customPoint = points.first { $0.id == custom.logID }
        #expect(customPoint?.title == "Mouth tape")
        #expect(customPoint?.nightsWithHabit == 1)
        #expect(customPoint?.avgWithHabitMinutes == 14)
        #expect(customPoint?.avgWithoutHabitMinutes == 6)
        #expect(customPoint?.systemImage == "tag.fill")
        #expect(customPoint?.deltaSummary == "+8m on nights you logged Mouth tape")
        #expect(customPoint?.expectedEffect == .unknown)
        #expect(customPoint?.expectedEffect.chipTitle == nil)
    }

    @Test func spokenDeltaUsesHabitClause() {
        let dayA = day(0)
        let dayB = day(-1)
        let nights = [
            DailySnorePoint(date: dayA, snoreMinutes: 22, eventCount: 4),
            DailySnorePoint(date: dayB, snoreMinutes: 9, eventCount: 2)
        ]
        let logs = [HabitLog(habitID: HabitKind.drankAlcohol.id, dayStart: dayA)]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: logs,
            exerciseDays: [],
            calendar: calendar
        )

        let alcohol = points.first { $0.id == HabitKind.drankAlcohol.id }
        #expect(alcohol?.systemImage == "wineglass.fill")
        #expect(alcohol?.deltaSummary == "+13m on nights you drank alcohol")
        #expect(alcohol?.isLowConfidence == true)
    }

    @Test func nearZeroDeltaReadsAsAboutTheSame() {
        let dayA = day(0)
        let dayB = day(-1)
        let nights = [
            DailySnorePoint(date: dayA, snoreMinutes: 10.4, eventCount: 2),
            DailySnorePoint(date: dayB, snoreMinutes: 10.2, eventCount: 2)
        ]
        let logs = [HabitLog(habitID: HabitKind.ateLate.id, dayStart: dayA)]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: logs,
            exerciseDays: [],
            calendar: calendar
        )

        let ateLate = points.first { $0.id == HabitKind.ateLate.id }
        #expect(ateLate?.deltaSummary == "About the same on nights you ate late")
    }

    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }
}

// MARK: - Quiet recorded nights vs missing nights
struct DailySnoreSessionPresenceTests {

    private let calendar = Calendar.current

    @Test func quietLoggedNightIsIncludedInTrend() {
        let points = [
            DailySnorePoint(date: day(0), snoreMinutes: 0, eventCount: 0, hadSession: true),
            DailySnorePoint(date: day(-1), snoreMinutes: 8, eventCount: 2, hadSession: true),
            DailySnorePoint(date: day(-2), snoreMinutes: 10, eventCount: 3, hadSession: true)
        ]

        #expect(AnalyticsViewModel.linearTrendLine(from: points) != nil)
        let insight = AnalyticsViewModel.makeInsight(from: points)
        #expect(insight.tone != .insufficientData)
    }

    @Test func unloggedNightIsExcludedFromTrend() {
        let points = [
            DailySnorePoint(date: day(0), snoreMinutes: 10, eventCount: 2, hadSession: true),
            DailySnorePoint(date: day(-1), snoreMinutes: 0, eventCount: 0, hadSession: false),
            DailySnorePoint(date: day(-2), snoreMinutes: 8, eventCount: 1, hadSession: true)
        ]

        #expect(AnalyticsViewModel.linearTrendLine(from: points) == nil)
        let insight = AnalyticsViewModel.makeInsight(from: points)
        #expect(insight.tone == .insufficientData)
    }

    @Test func quietLoggedNightCanBeBestDay() {
        let days = [
            DailySnorePoint(date: day(0), snoreMinutes: 0, eventCount: 0, hadSession: true),
            DailySnorePoint(date: day(-1), snoreMinutes: 8, eventCount: 2, hadSession: true)
        ]

        let best = AnalyticsViewModel.extremeSnoreDay(in: days, preferMinimum: true)
        let worst = AnalyticsViewModel.extremeSnoreDay(in: days, preferMinimum: false)
        #expect(best?.snoreMinutes == 0)
        #expect(worst?.snoreMinutes == 8)
    }

    @Test func missingNightIsNotBestOrWorst() {
        let days = [
            DailySnorePoint(date: day(0), snoreMinutes: 0, eventCount: 0, hadSession: false),
            DailySnorePoint(date: day(-1), snoreMinutes: 8, eventCount: 2, hadSession: true)
        ]

        let best = AnalyticsViewModel.extremeSnoreDay(in: days, preferMinimum: true)
        #expect(best?.snoreMinutes == 8)
    }

    @Test func quietLoggedNightsAreIncludedInHabitCorrelation() {
        let dayA = day(0)
        let dayB = day(-1)
        let nights = [
            DailySnorePoint(date: dayA, snoreMinutes: 10, eventCount: 2, hadSession: true),
            DailySnorePoint(date: dayB, snoreMinutes: 0, eventCount: 0, hadSession: true)
        ]
        let logs = [HabitLog(habitID: HabitKind.ateLate.id, dayStart: dayA)]

        let points = AnalyticsViewModel.buildHabitCorrelationPoints(
            sessionNights: nights,
            habitLogs: logs,
            exerciseDays: [],
            calendar: calendar
        )

        let ateLate = points.first { $0.id == HabitKind.ateLate.id }
        #expect(ateLate?.avgWithHabitMinutes == 10)
        #expect(ateLate?.avgWithoutHabitMinutes == 0)
        #expect(ateLate?.nightsWithoutHabit == 1)
    }

    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }
}

// MARK: - Trend banner habit copy
struct InsightHabitCopyTests {

    private let calendar = Calendar.current

    @Test func weekTrendingUpPointsToHabitsWithoutDelta() {
        let alcohol = habit(.drankAlcohol, withMinutes: 20, withoutMinutes: 7)
        let insight = AnalyticsViewModel.makeInsight(
            from: nights([2, 8, 16]),
            habits: [alcohol],
            range: .week
        )
        #expect(insight.tone == .trendingUp)
        #expect(insight.text == "Your snoring is trending up this period. Review Habits or try adjusting alerts.")
        #expect(!insight.text.contains("+13m"))
    }

    @Test func weekFlatPromptsLoggingHabits() {
        let insight = AnalyticsViewModel.makeInsight(
            from: nights([8, 8, 8]),
            habits: [],
            range: .week
        )
        #expect(insight.tone == .flat)
        #expect(insight.text.contains("Log habits to see what tracks with your nights."))
    }

    @Test func monthTrendingUpQuotesStrongestMayAddHabit() {
        let alcohol = habit(.drankAlcohol, withMinutes: 20, withoutMinutes: 7)
        let insight = AnalyticsViewModel.makeInsight(
            from: nights([2, 8, 16]),
            habits: [alcohol],
            range: .month
        )
        #expect(insight.tone == .trendingUp)
        #expect(insight.text == "Your snoring is trending up this period. Snoring ran +13m on nights you drank alcohol.")
    }

    @Test func monthTrendingDownQuotesMayHelpHabit() {
        let exercise = habit(.myofascialExercise, withMinutes: 6, withoutMinutes: 14)
        let insight = AnalyticsViewModel.makeInsight(
            from: nights([16, 8, 2]),
            habits: [exercise],
            range: .month
        )
        #expect(insight.tone == .trendingDown)
        #expect(insight.text == "Your snoring is trending down. −8m on nights you did airway exercises. Keep it up.")
    }

    @Test func monthFlatQuotesLargestHabitDelta() {
        let alcohol = habit(.drankAlcohol, withMinutes: 20, withoutMinutes: 7)
        let insight = AnalyticsViewModel.makeInsight(
            from: nights([8, 8, 8]),
            habits: [alcohol],
            range: .month
        )
        #expect(insight.tone == .flat)
        #expect(insight.text == "Your snoring looks about the same this period. Individual nights still differ — +13m on nights you drank alcohol.")
    }

    @Test func monthSkipsLowConfidenceHabit() {
        let early = habit(.drankAlcohol, withMinutes: 20, withoutMinutes: 7, nights: 2)
        let insight = AnalyticsViewModel.makeInsight(
            from: nights([2, 8, 16]),
            habits: [early],
            range: .month
        )
        #expect(insight.tone == .trendingUp)
        #expect(insight.text == "Your snoring is trending up this period. Review History or try adjusting alerts.")
    }

    @Test func trendingUpPrefersMayAddOverLargerMayHelpDelta() {
        let alcohol = habit(.drankAlcohol, withMinutes: 18, withoutMinutes: 8)
        let exercise = habit(.myofascialExercise, withMinutes: 30, withoutMinutes: 8)
        let picked = AnalyticsViewModel.supportingHabit(
            for: .trendingUp,
            in: [exercise, alcohol]
        )
        #expect(picked?.id == HabitKind.drankAlcohol.id)
    }

    @Test func trendingDownPrefersMayHelpOverLargerMayAddDrop() {
        let alcohol = habit(.drankAlcohol, withMinutes: 4, withoutMinutes: 24)
        let exercise = habit(.myofascialExercise, withMinutes: 6, withoutMinutes: 14)
        let picked = AnalyticsViewModel.supportingHabit(
            for: .trendingDown,
            in: [alcohol, exercise]
        )
        #expect(picked?.id == HabitKind.myofascialExercise.id)
    }

    private func nights(_ minutes: [Double]) -> [DailySnorePoint] {
        minutes.enumerated().map { index, value in
            DailySnorePoint(
                date: day(-minutes.count + 1 + index),
                snoreMinutes: value,
                eventCount: value > 0 ? 2 : 0,
                hadSession: true
            )
        }
    }

    private func habit(
        _ kind: HabitKind,
        withMinutes: Double,
        withoutMinutes: Double,
        nights: Int = 3
    ) -> HabitCorrelationPoint {
        HabitCorrelationPoint(
            id: kind.id,
            title: kind.title,
            systemImage: kind.systemImage,
            insightClause: kind.insightClause,
            expectedEffect: kind.expectedEffect,
            avgWithHabitMinutes: withMinutes,
            avgWithoutHabitMinutes: withoutMinutes,
            nightsWithHabit: nights,
            nightsWithoutHabit: nights
        )
    }

    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }
}
