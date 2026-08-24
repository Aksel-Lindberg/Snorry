import Foundation
import Testing
@testable import Snorry

// MARK: - Habits tab grouping
struct HabitGroupingTests {

    @Test func habitsTabLeadsWithMayReduceSnoring() {
        #expect(
            HabitExpectedEffect.habitsTabSections == [
                .mayHelp, .mayAddSnoring, .howYouFelt, .unknown
            ]
        )
        #expect(HabitExpectedEffect.mayHelp.sectionTitle == "May reduce snoring")
        #expect(HabitExpectedEffect.howYouFelt.chipTitle == "How you felt")
    }

    @Test func mayHelpLeadsWithAirwayExercises() {
        let habits = HabitDefinition.inSection(.mayHelp, customHabits: [])
        #expect(habits.compactMap(\.builtInKind) == [
            .myofascialExercise, .nasalSpray, .nasalClip
        ])
    }

    @Test func congestedLivesInHowYouFeltNotMayAdd() {
        #expect(HabitKind.congested.expectedEffect == .howYouFelt)
        #expect(HabitKind.congested.expectedEffect.typicallyAddsSnoring)

        let mayAdd = HabitDefinition.inSection(.mayAddSnoring, customHabits: [])
        #expect(mayAdd.compactMap(\.builtInKind) == [
            .ateLate, .drankAlcohol, .caffeineLate, .sleptOnBack
        ])

        let felt = HabitDefinition.inSection(.howYouFelt, customHabits: [])
        #expect(felt.compactMap(\.builtInKind) == [.congested])
    }
}

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
        #expect(congested?.expectedEffect == .howYouFelt)
        #expect(congested?.expectedEffect.chipTitle == "How you felt")
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

    @Test func signedDeltaLabelShowsSignedMinutes() {
        let caffeine = habit(.caffeineLate, withMinutes: 17, withoutMinutes: 7)
        #expect(caffeine.signedDeltaLabel == "+10m")
        #expect(caffeine.deltaSummary == "+10m on nights you had caffeine late")

        let exercise = habit(.myofascialExercise, withMinutes: 4, withoutMinutes: 10)
        #expect(exercise.signedDeltaLabel == "−6m")

        let flat = habit(.ateLate, withMinutes: 8, withoutMinutes: 8.5)
        #expect(flat.signedDeltaLabel == nil)
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

    @Test func trendLineSpansRecordedNightsOnly() {
        let points = [
            DailySnorePoint(date: day(-10), snoreMinutes: 0, eventCount: 0, hadSession: false),
            DailySnorePoint(date: day(-9), snoreMinutes: 0, eventCount: 0, hadSession: false),
            DailySnorePoint(date: day(-2), snoreMinutes: 20, eventCount: 4, hadSession: true),
            DailySnorePoint(date: day(-1), snoreMinutes: 15, eventCount: 3, hadSession: true),
            DailySnorePoint(date: day(0), snoreMinutes: 10, eventCount: 2, hadSession: true)
        ]

        let trend = AnalyticsViewModel.linearTrendLine(from: points)
        #expect(trend?.count == 2)
        #expect(trend?.first?.date == day(-2))
        #expect(trend?.last?.date == day(0))
        #expect(trend!.first!.predictedMinutes > trend!.last!.predictedMinutes)
    }

    @Test func leadingGapsDoNotAffectTrendDirection() {
        let dense = [
            DailySnorePoint(date: day(-2), snoreMinutes: 20, eventCount: 4, hadSession: true),
            DailySnorePoint(date: day(-1), snoreMinutes: 15, eventCount: 3, hadSession: true),
            DailySnorePoint(date: day(0), snoreMinutes: 10, eventCount: 2, hadSession: true)
        ]
        let withGaps = [
            DailySnorePoint(date: day(-30), snoreMinutes: 0, eventCount: 0, hadSession: false),
            DailySnorePoint(date: day(-29), snoreMinutes: 0, eventCount: 0, hadSession: false),
            DailySnorePoint(date: day(-2), snoreMinutes: 20, eventCount: 4, hadSession: true),
            DailySnorePoint(date: day(-1), snoreMinutes: 15, eventCount: 3, hadSession: true),
            DailySnorePoint(date: day(0), snoreMinutes: 10, eventCount: 2, hadSession: true)
        ]

        let denseTrend = AnalyticsViewModel.linearTrendLine(from: dense)
        let gapTrend = AnalyticsViewModel.linearTrendLine(from: withGaps)
        #expect(denseTrend?.first?.predictedMinutes == gapTrend?.first?.predictedMinutes)
        #expect(denseTrend?.last?.predictedMinutes == gapTrend?.last?.predictedMinutes)

        let denseInsight = AnalyticsViewModel.makeInsight(from: dense)
        let gapInsight = AnalyticsViewModel.makeInsight(from: withGaps)
        #expect(denseInsight.tone == gapInsight.tone)
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

// MARK: - Calendar week / month paging
struct AnalyticsPeriodBoundsTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test func thisWeekCapsAtToday() {
        let wednesday = date(2026, 8, 19)
        let bounds = AnalyticsViewModel.visibleBounds(
            range: .week,
            offset: 0,
            now: wednesday,
            calendar: calendar
        )
        #expect(bounds?.start == date(2026, 8, 17))
        #expect(bounds?.lastDayStart == date(2026, 8, 19))
        #expect(bounds?.endExclusive == date(2026, 8, 20))
    }

    @Test func previousWeekIsFullSevenDays() {
        let wednesday = date(2026, 8, 19)
        let thisWeek = AnalyticsViewModel.visibleBounds(
            range: .week,
            offset: 0,
            now: wednesday,
            calendar: calendar
        )
        let previous = AnalyticsViewModel.previousBounds(
            before: thisWeek!.start,
            range: .week,
            calendar: calendar
        )
        #expect(previous?.start == date(2026, 8, 10))
        #expect(previous?.lastDayStart == date(2026, 8, 16))
        #expect(previous?.endExclusive == date(2026, 8, 17))
    }

    @Test func thisMonthCapsAtToday() {
        let wednesday = date(2026, 8, 19)
        let bounds = AnalyticsViewModel.visibleBounds(
            range: .month,
            offset: 0,
            now: wednesday,
            calendar: calendar
        )
        #expect(bounds?.start == date(2026, 8, 1))
        #expect(bounds?.lastDayStart == date(2026, 8, 19))
        #expect(bounds?.endExclusive == date(2026, 8, 20))
    }

    @Test func previousMonthIsFullCalendarMonth() {
        let wednesday = date(2026, 8, 19)
        let thisMonth = AnalyticsViewModel.visibleBounds(
            range: .month,
            offset: 0,
            now: wednesday,
            calendar: calendar
        )
        let previous = AnalyticsViewModel.previousBounds(
            before: thisMonth!.start,
            range: .month,
            calendar: calendar
        )
        #expect(previous?.start == date(2026, 7, 1))
        #expect(previous?.lastDayStart == date(2026, 7, 31))
        #expect(previous?.endExclusive == date(2026, 8, 1))
    }

    @Test func threeMonthsDoesNotPage() {
        let now = date(2026, 8, 19)
        #expect(
            AnalyticsViewModel.visibleBounds(
                range: .threeMonths,
                offset: -1,
                now: now,
                calendar: calendar
            ) == nil
        )
        #expect(AnalyticsRange.threeMonths.allowsPaging == false)
    }

    @Test func threeMonthsPreviousBoundsIsPrior90DayBlock() {
        let now = date(2026, 8, 19)
        let current = AnalyticsViewModel.visibleBounds(
            range: .threeMonths,
            offset: 0,
            now: now,
            calendar: calendar
        )
        let previous = AnalyticsViewModel.previousBounds(
            before: current!.start,
            range: .threeMonths,
            calendar: calendar
        )

        let expectedStart = calendar.date(byAdding: .day, value: -90, to: current!.start)!
        let expectedLastDay = calendar.date(byAdding: .day, value: -1, to: previous!.endExclusive)!

        #expect(previous?.start == calendar.startOfDay(for: expectedStart))
        #expect(previous?.endExclusive == current?.start)
        #expect(previous?.lastDayStart == calendar.startOfDay(for: expectedLastDay))
    }

    @Test func hasComparablePreviousPeriodRequiresRecordedSessions() {
        #expect(AnalyticsViewModel.hasComparablePreviousPeriod(previousSessionCount: 0) == false)
        #expect(AnalyticsViewModel.hasComparablePreviousPeriod(previousSessionCount: 3) == true)
    }

    @Test func cannotPageBackBeforeOldestSessionWeek() {
        let now = date(2026, 8, 19)
        #expect(
            AnalyticsViewModel.canPageBack(
                range: .week,
                offset: 0,
                now: now,
                oldestSession: date(2026, 8, 18),
                calendar: calendar
            ) == false
        )
        #expect(
            AnalyticsViewModel.canPageBack(
                range: .week,
                offset: 0,
                now: now,
                oldestSession: date(2026, 8, 10),
                calendar: calendar
            ) == true
        )
    }

    @Test func weekRangeLabelOmitsRepeatedMonth() {
        let label = AnalyticsViewModel.weekRangeLabel(
            from: date(2026, 8, 17),
            through: date(2026, 8, 23)
        )
        #expect(label.contains("17"))
        #expect(label.contains("23"))
        #expect(label.contains("Aug"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

// MARK: - Sleep night bucketing
struct SleepNightTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test func beforeSixAMMapsToPreviousNight() {
        let night = SleepNight.dayStart(
            for: dateTime(2026, 8, 17, hour: 0, minute: 52),
            calendar: calendar
        )
        #expect(night == date(2026, 8, 16))
    }

    @Test func fiveFiftyNineMapsToPreviousNight() {
        let night = SleepNight.dayStart(
            for: dateTime(2026, 8, 17, hour: 5, minute: 59),
            calendar: calendar
        )
        #expect(night == date(2026, 8, 16))
    }

    @Test func sixAMStaysOnSameCalendarDay() {
        let night = SleepNight.dayStart(
            for: dateTime(2026, 8, 17, hour: 6, minute: 0),
            calendar: calendar
        )
        #expect(night == date(2026, 8, 17))
    }

    @Test func lateEveningStaysOnSameCalendarDay() {
        let night = SleepNight.dayStart(
            for: dateTime(2026, 8, 17, hour: 23, minute: 11),
            calendar: calendar
        )
        #expect(night == date(2026, 8, 17))
    }

    @Test func sameCalendarDateDifferentSleepNightsProduceTwoBuckets() {
        let sessions = [
            makeSession(start: dateTime(2026, 8, 17, hour: 0, minute: 52), minutes: 0, events: 0),
            makeSession(start: dateTime(2026, 8, 17, hour: 23, minute: 11), minutes: 3, events: 12)
        ]
        let aggregated = SleepNight.aggregateByNight(sessions: sessions, calendar: calendar)
        #expect(aggregated.durationByDay.count == 2)
        #expect(aggregated.durationByDay[date(2026, 8, 16)] == 0)
        #expect(aggregated.durationByDay[date(2026, 8, 17)] == 3)
        #expect(aggregated.eventsByDay[date(2026, 8, 16)] == 0)
        #expect(aggregated.eventsByDay[date(2026, 8, 17)] == 12)
    }

    @Test func twoRecordingsSameSleepNightAreSummed() {
        let sessions = [
            makeSession(start: dateTime(2026, 8, 17, hour: 22, minute: 30), minutes: 2, events: 4),
            makeSession(start: dateTime(2026, 8, 17, hour: 23, minute: 45), minutes: 5, events: 8)
        ]
        let aggregated = SleepNight.aggregateByNight(sessions: sessions, calendar: calendar)
        #expect(aggregated.durationByDay.count == 1)
        #expect(aggregated.durationByDay[date(2026, 8, 17)] == 7)
        #expect(aggregated.eventsByDay[date(2026, 8, 17)] == 12)
        #expect(aggregated.sessionsByDay[date(2026, 8, 17)]?.count == 2)
    }

    @Test func afterMidnightSessionBelongsToPreviousWeek() {
        let session = makeSession(
            start: dateTime(2026, 8, 17, hour: 0, minute: 52),
            minutes: 0,
            events: 0
        )
        let previousWeekEnd = date(2026, 8, 16)
        let currentWeekStart = date(2026, 8, 17)

        let inPreviousWeek = SleepNight.completedSessions(
            in: [session],
            rangeStart: date(2026, 8, 10),
            rangeEnd: previousWeekEnd,
            calendar: calendar
        )
        let inCurrentWeek = SleepNight.completedSessions(
            in: [session],
            rangeStart: currentWeekStart,
            rangeEnd: date(2026, 8, 19),
            calendar: calendar
        )

        #expect(inPreviousWeek.count == 1)
        #expect(inCurrentWeek.isEmpty)
    }

    @Test func canPageBackWhenOldestSessionIsAfterMidnightMonday() {
        let now = dateTime(2026, 8, 19, hour: 12)
        let oldestSession = dateTime(2026, 8, 17, hour: 0, minute: 52)
        #expect(
            AnalyticsViewModel.canPageBack(
                range: .week,
                offset: 0,
                now: now,
                oldestSession: oldestSession,
                calendar: calendar
            )
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateTime(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeSession(start: Date, minutes: Double, events: Int) -> SnoreSession {
        let session = SnoreSession(startDate: start)
        session.endDate = start.addingTimeInterval(6 * 3600)
        session.totalSnoreDuration = minutes * 60
        session.eventCount = events
        return session
    }
}
