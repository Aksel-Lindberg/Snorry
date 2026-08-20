import Foundation
import SwiftData
import Observation

// MARK: - Time window options for the analytics screen
enum AnalyticsRange: String, CaseIterable, Identifiable {
    case week        = "Week"
    case month       = "Month"
    case threeMonths = "3 Months"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week:        return 7
        case .month:       return 30
        case .threeMonths: return 90
        }
    }

    /// Wording for period-over-period KPI subtitles.
    var previousPeriodLabel: String {
        switch self {
        case .week:        return "last week"
        case .month:       return "last month"
        case .threeMonths: return "prior 3 months"
        }
    }

    /// Habit comparisons need more than a week of nights.
    var showsHabitCorrelation: Bool { self != .week }
}

// MARK: - Aggregated snore data for one calendar day
struct DailySnorePoint: Identifiable {
    let id = UUID()
    /// Start-of-day date in the local calendar.
    let date: Date
    /// Total snore duration across all completed sessions that day, in minutes.
    let snoreMinutes: Double
    /// Total snore event count across all completed sessions that day.
    let eventCount: Int

    var hadSession: Bool { eventCount > 0 || snoreMinutes > 0 }
}

// MARK: - One alert-profile bucket for the correlation chart
struct AlertProfilePoint: Identifiable {
    let id = UUID()
    /// Short, human-readable label for this profile (e.g. "Push · Classic").
    let label: String
    /// Average snore duration per session with this profile, in minutes.
    let avgSnoreMinutes: Double
    /// Number of sessions in this bucket.
    let sessionCount: Int
    /// True when sessionCount is small enough that the average may not be representative.
    var isLowConfidence: Bool { sessionCount < 3 }
}

// MARK: - One habit bucket for the correlation chart
struct HabitCorrelationPoint: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    /// Spoken clause after the delta (“on nights you drank alcohol”).
    let insightClause: String
    /// Typical direction for built-in habits; custom is `.unknown`.
    let expectedEffect: HabitExpectedEffect
    /// Average snore minutes on nights when this habit was logged.
    let avgWithHabitMinutes: Double
    /// Average snore minutes on nights when this habit was not logged.
    let avgWithoutHabitMinutes: Double
    let nightsWithHabit: Int
    let nightsWithoutHabit: Int

    /// Positive delta means more snoring when the habit was present.
    var deltaMinutes: Double { avgWithHabitMinutes - avgWithoutHabitMinutes }

    var isLowConfidenceWith: Bool { nightsWithHabit < 3 }
    var isLowConfidenceWithout: Bool { nightsWithoutHabit < 3 }
    var isLowConfidence: Bool { isLowConfidenceWith || isLowConfidenceWithout }

    /// One-line finding for the selected habit.
    var deltaSummary: String {
        if abs(deltaMinutes) < 1 {
            return "About the same \(insightClause)"
        }
        let sign = deltaMinutes > 0 ? "+" : "−"
        return "\(sign)\(Self.minuteLabel(abs(deltaMinutes))) \(insightClause)"
    }

    static func minuteLabel(_ minutes: Double) -> String {
        if minutes < 1 { return "<1m" }
        let total = Int(minutes.rounded())
        let hours = total / 60
        let remainder = total % 60
        if hours > 0 {
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(remainder)m"
    }
}

// MARK: - Metrics for one analytics time window
struct PeriodSnapshot {
    let sessionCount: Int
    /// Mean daily snore minutes over nights that had at least one completed session.
    let averageDailySnoreMinutes: Double
    /// Nights with total snore below the good-night threshold.
    let nightsUnderThreshold: Int
    let dailyPoints: [DailySnorePoint]
    let sessionsByDay: [Date: [SnoreSession]]

    var sessionDays: [DailySnorePoint] {
        dailyPoints.filter(\.hadSession)
    }
}

// MARK: - Narrative insight from snore duration trend
enum InsightTone {
    case trendingDown
    case trendingUp
    case flat
    case insufficientData
}

struct InsightMessage {
    let tone: InsightTone
    let text: String
}

/// One point on the linear trend overlay (start/end of the visible range).
struct TrendLinePoint: Identifiable {
    let id = UUID()
    let date: Date
    let predictedMinutes: Double
}

// MARK: - Analytics view model
@Observable
@MainActor
final class AnalyticsViewModel {

    var selectedRange: AnalyticsRange = .week
    var currentPeriod = PeriodSnapshot(
        sessionCount: 0,
        averageDailySnoreMinutes: 0,
        nightsUnderThreshold: 0,
        dailyPoints: [],
        sessionsByDay: [:]
    )
    var previousPeriod = PeriodSnapshot(
        sessionCount: 0,
        averageDailySnoreMinutes: 0,
        nightsUnderThreshold: 0,
        dailyPoints: [],
        sessionsByDay: [:]
    )
    var settingsChanges: [AlertSettingsChange] = []
    var alertProfilePoints: [AlertProfilePoint] = []
    var habitCorrelationPoints: [HabitCorrelationPoint] = []
    var exerciseLoggedDayStarts: Set<Date> = []

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    // MARK: Current period (UI convenience)

    var dailyPoints: [DailySnorePoint] { currentPeriod.dailyPoints }
    var sessionCount: Int { currentPeriod.sessionCount }
    var sessionsByDay: [Date: [SnoreSession]] { currentPeriod.sessionsByDay }

    var averageDailySnoreMinutes: Double { currentPeriod.averageDailySnoreMinutes }

    var insightMessage: InsightMessage {
        Self.makeInsight(from: currentPeriod.dailyPoints)
    }

    var trendLinePoints: [TrendLinePoint]? {
        Self.linearTrendLine(from: currentPeriod.dailyPoints)
    }

    var bestSnoreDay: DailySnorePoint? {
        Self.extremeSnoreDay(in: currentPeriod.sessionDays, preferMinimum: true)
    }

    var worstSnoreDay: DailySnorePoint? {
        Self.extremeSnoreDay(in: currentPeriod.sessionDays, preferMinimum: false)
    }

    var hasSessionDataInPeriod: Bool { !currentPeriod.sessionDays.isEmpty }

    var averageDurationPercentChange: Double? {
        Self.percentChange(
            current: currentPeriod.averageDailySnoreMinutes,
            previous: previousPeriod.averageDailySnoreMinutes
        )
    }

    var sessionCountDelta: Int {
        currentPeriod.sessionCount - previousPeriod.sessionCount
    }

    var goodNightsDelta: Int {
        currentPeriod.nightsUnderThreshold - previousPeriod.nightsUnderThreshold
    }

    // MARK: Data loading

    func refresh() {
        let cal = Calendar.current
        let now = Date()
        guard let cutoff = cal.date(byAdding: .day, value: -selectedRange.days, to: now),
              let previousCutoff = cal.date(byAdding: .day, value: -selectedRange.days, to: cutoff) else {
            return
        }

        let rangeStart = cal.startOfDay(for: previousCutoff)
        let currentCutoff = cutoff

        let sessions = fetchSessions(since: rangeStart)
        currentPeriod = Self.buildPeriodSnapshot(
            sessions: sessions.filter { $0.startDate >= currentCutoff },
            rangeStart: cal.startOfDay(for: currentCutoff),
            rangeEnd: cal.startOfDay(for: now),
            calendar: cal
        )
        previousPeriod = Self.buildPeriodSnapshot(
            sessions: sessions.filter { $0.startDate >= rangeStart && $0.startDate < currentCutoff },
            rangeStart: rangeStart,
            rangeEnd: cal.startOfDay(for: currentCutoff),
            calendar: cal
        )

        loadSettingsChanges(since: currentCutoff)
        loadAlertCorrelation(since: currentCutoff)
        loadExerciseDays(since: currentCutoff, calendar: cal)
        loadHabitCorrelation(since: currentCutoff, calendar: cal)
    }

    func sessions(on dayStart: Date) -> [SnoreSession] {
        let cal = Calendar.current
        let key = cal.startOfDay(for: dayStart)
        return sessionsByDay[key] ?? []
    }

    func session(withID id: UUID) -> SnoreSession? {
        for sessions in sessionsByDay.values {
            if let match = sessions.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// Deletes one saved settings-change marker and refreshes analytics state.
    func deleteSettingsChange(_ change: AlertSettingsChange) {
        context.delete(change)
        do {
            try context.save()
        } catch {
            context.rollback()
            return
        }
        refresh()
    }

    // MARK: Computed chart helpers

    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
    }

    var snoreMinutesYMax: Double {
        let peak = dailyPoints.map(\.snoreMinutes).max() ?? 0
        guard peak > 0 else { return 10 }
        let step: Double = peak < 15 ? 5 : peak < 60 ? 10 : 30
        return ceil((peak + step * 0.2) / step) * step
    }

    var eventCountYMax: Double {
        let peak = Double(dailyPoints.map(\.eventCount).max() ?? 0)
        guard peak > 0 else { return 5 }
        let step: Double = peak < 10 ? 2 : peak < 30 ? 5 : 10
        return ceil((peak + step * 0.2) / step) * step
    }

    var alertChartXMax: Double {
        let peak = alertProfilePoints.map(\.avgSnoreMinutes).max() ?? 0
        guard peak > 0 else { return 10 }
        let step: Double = peak < 15 ? 5 : peak < 60 ? 10 : 30
        return ceil((peak + step * 0.2) / step) * step
    }

    // MARK: Private helpers

    private func fetchSessions(since rangeStart: Date) -> [SnoreSession] {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= rangeStart },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func buildPeriodSnapshot(
        sessions: [SnoreSession],
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> PeriodSnapshot {
        var durationByDay: [Date: Double] = [:]
        var eventsByDay: [Date: Int] = [:]
        var sessionsByDay: [Date: [SnoreSession]] = [:]
        var totalSessions = 0

        for session in sessions where session.endDate != nil {
            let day = calendar.startOfDay(for: session.startDate)
            durationByDay[day, default: 0] += session.totalSnoreDuration / 60.0
            eventsByDay[day, default: 0] += session.displayEventCount
            sessionsByDay[day, default: []].append(session)
            totalSessions += 1
        }

        for key in sessionsByDay.keys {
            sessionsByDay[key]?.sort { $0.startDate > $1.startDate }
        }

        let threshold = InsightsConfiguration.goodNightSnoreMinutesThreshold
        var nightsUnder = 0
        for day in durationByDay.keys {
            if (durationByDay[day] ?? 0) < threshold {
                nightsUnder += 1
            }
        }

        let sessionDayPoints = durationByDay.keys.map { day in
            DailySnorePoint(
                date: day,
                snoreMinutes: durationByDay[day] ?? 0,
                eventCount: eventsByDay[day] ?? 0
            )
        }
        let avgMinutes: Double = {
            guard !sessionDayPoints.isEmpty else { return 0 }
            let sum = sessionDayPoints.map(\.snoreMinutes).reduce(0, +)
            return sum / Double(sessionDayPoints.count)
        }()

        let densePoints = denseDailySeries(
            from: rangeStart,
            through: rangeEnd,
            durationByDay: durationByDay,
            eventsByDay: eventsByDay,
            calendar: calendar
        )

        return PeriodSnapshot(
            sessionCount: totalSessions,
            averageDailySnoreMinutes: avgMinutes,
            nightsUnderThreshold: nightsUnder,
            dailyPoints: densePoints,
            sessionsByDay: sessionsByDay
        )
    }

    private static func denseDailySeries(
        from rangeStart: Date,
        through rangeEnd: Date,
        durationByDay: [Date: Double],
        eventsByDay: [Date: Int],
        calendar: Calendar
    ) -> [DailySnorePoint] {
        var points: [DailySnorePoint] = []
        var cursor = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)

        while cursor <= end {
            points.append(
                DailySnorePoint(
                    date: cursor,
                    snoreMinutes: durationByDay[cursor] ?? 0,
                    eventCount: eventsByDay[cursor] ?? 0
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    private func loadSettingsChanges(since cutoff: Date) {
        let descriptor = FetchDescriptor<AlertSettingsChange>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        settingsChanges = (try? context.fetch(descriptor)) ?? []
    }

    private func loadExerciseDays(since cutoff: Date, calendar: Calendar) {
        let descriptor = FetchDescriptor<MyofascialExerciseCompletion>(
            predicate: #Predicate { $0.completedAt >= cutoff },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        exerciseLoggedDayStarts = Set(rows.map { calendar.startOfDay(for: $0.completedAt) })
    }

    private func loadHabitCorrelation(since cutoff: Date, calendar: Calendar) {
        let habitDescriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.dayStart >= cutoff },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let habitLogs = (try? context.fetch(habitDescriptor)) ?? []

        let exerciseDescriptor = FetchDescriptor<MyofascialExerciseCompletion>(
            predicate: #Predicate { $0.completedAt >= cutoff },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        let exerciseRows = (try? context.fetch(exerciseDescriptor)) ?? []
        let exerciseDays = Set(exerciseRows.map { calendar.startOfDay(for: $0.completedAt) })

        let customDescriptor = FetchDescriptor<CustomHabit>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let customHabits = (try? context.fetch(customDescriptor)) ?? []

        let sessionNights = currentPeriod.sessionDays
        guard !sessionNights.isEmpty else {
            habitCorrelationPoints = []
            return
        }

        habitCorrelationPoints = Self.buildHabitCorrelationPoints(
            sessionNights: sessionNights,
            habitLogs: habitLogs,
            exerciseDays: exerciseDays,
            customHabits: customHabits,
            calendar: calendar
        )
    }

    static func buildHabitCorrelationPoints(
        sessionNights: [DailySnorePoint],
        habitLogs: [HabitLog],
        exerciseDays: Set<Date>,
        customHabits: [CustomHabit] = [],
        calendar: Calendar
    ) -> [HabitCorrelationPoint] {
        buildHabitCorrelationPoints(
            sessionNights: sessionNights,
            habitLogs: habitLogs,
            exerciseDays: exerciseDays,
            habits: HabitDefinition.all(customHabits: customHabits),
            calendar: calendar
        )
    }

    static func buildHabitCorrelationPoints(
        sessionNights: [DailySnorePoint],
        habitLogs: [HabitLog],
        exerciseDays: Set<Date>,
        habits: [HabitDefinition],
        calendar: Calendar
    ) -> [HabitCorrelationPoint] {
        var points: [HabitCorrelationPoint] = []

        for habit in habits {
            let loggedDays = HabitLog.loggedDayStarts(
                forHabitID: habit.id,
                in: habitLogs,
                since: .distantPast,
                calendar: calendar
            )
            let effectiveDays: Set<Date>
            if habit.builtInKind == .myofascialExercise {
                effectiveDays = loggedDays.union(exerciseDays)
            } else {
                effectiveDays = loggedDays
            }

            guard effectiveDays.contains(where: { day in
                sessionNights.contains { calendar.isDate($0.date, inSameDayAs: day) }
            }) else { continue }

            var withValues: [Double] = []
            var withoutValues: [Double] = []

            for night in sessionNights {
                let day = calendar.startOfDay(for: night.date)
                if effectiveDays.contains(day) {
                    withValues.append(night.snoreMinutes)
                } else {
                    withoutValues.append(night.snoreMinutes)
                }
            }

            guard !withValues.isEmpty else { continue }

            points.append(
                HabitCorrelationPoint(
                    id: habit.id,
                    title: habit.title,
                    systemImage: habit.systemImage,
                    insightClause: habit.insightClause,
                    expectedEffect: habit.expectedEffect,
                    avgWithHabitMinutes: withValues.reduce(0, +) / Double(withValues.count),
                    avgWithoutHabitMinutes: withoutValues.isEmpty
                        ? 0
                        : withoutValues.reduce(0, +) / Double(withoutValues.count),
                    nightsWithHabit: withValues.count,
                    nightsWithoutHabit: withoutValues.count
                )
            )
        }

        return points.sorted { abs($0.deltaMinutes) > abs($1.deltaMinutes) }
    }

    private func loadAlertCorrelation(since cutoff: Date) {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= cutoff },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        let qualified = sessions.filter { s in
            s.endDate != nil &&
            s.snapshotPushEnabled != nil &&
            s.snapshotSoundEnabled != nil &&
            s.snapshotAlarmStyleRaw != nil
        }

        var buckets: [String: [Double]] = [:]
        for s in qualified {
            let label = Self.profileLabel(
                push: s.snapshotPushEnabled!,
                sound: s.snapshotSoundEnabled!,
                styleRaw: s.snapshotAlarmStyleRaw!
            )
            buckets[label, default: []].append(s.totalSnoreDuration / 60.0)
        }

        alertProfilePoints = buckets
            .map { label, values in
                AlertProfilePoint(
                    label: label,
                    avgSnoreMinutes: values.reduce(0, +) / Double(values.count),
                    sessionCount: values.count
                )
            }
            .sorted { $0.avgSnoreMinutes < $1.avgSnoreMinutes }
    }

    private static func profileLabel(push: Bool, sound: Bool, styleRaw: Int) -> String {
        let styleName = AlarmStyle(rawValue: styleRaw)?.displayName ?? "Sound"
        switch (push, sound) {
        case (true,  true):  return "Push · \(styleName)"
        case (true,  false): return "Push only"
        case (false, true):  return styleName
        case (false, false): return "No alerts"
        }
    }

    // MARK: Trend & insight

    static func linearTrendLine(from dailyPoints: [DailySnorePoint]) -> [TrendLinePoint]? {
        let indexed: [(x: Double, y: Double, date: Date)] = dailyPoints.enumerated().compactMap { index, point in
            guard point.hadSession else { return nil }
            return (Double(index), point.snoreMinutes, point.date)
        }
        guard indexed.count >= InsightsConfiguration.minimumNightsForTrend else { return nil }

        let n = Double(indexed.count)
        let sumX = indexed.map(\.x).reduce(0, +)
        let sumY = indexed.map(\.y).reduce(0, +)
        let sumXY = indexed.reduce(0.0) { $0 + $1.x * $1.y }
        let sumX2 = indexed.map { $0.x * $0.x }.reduce(0, +)
        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.0001 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        guard let first = dailyPoints.first, let last = dailyPoints.last else { return nil }
        let firstIndex = 0.0
        let lastIndex = Double(max(dailyPoints.count - 1, 0))

        return [
            TrendLinePoint(date: first.date, predictedMinutes: max(0, intercept + slope * firstIndex)),
            TrendLinePoint(date: last.date, predictedMinutes: max(0, intercept + slope * lastIndex))
        ]
    }

    static func makeInsight(from dailyPoints: [DailySnorePoint]) -> InsightMessage {
        let sessionDays = dailyPoints.filter(\.hadSession)
        guard !sessionDays.isEmpty else {
            return InsightMessage(
                tone: .insufficientData,
                text: "Start a recording session to see how your snoring trends over time."
            )
        }

        guard sessionDays.count >= InsightsConfiguration.minimumNightsForTrend,
              let trend = linearTrendLine(from: dailyPoints),
              trend.count == 2 else {
            return InsightMessage(
                tone: .insufficientData,
                text: "Log a few more nights to see whether your snoring is trending up or down."
            )
        }

        let slopePerDay = (trend[1].predictedMinutes - trend[0].predictedMinutes) /
            Double(max(dailyPoints.count - 1, 1))
        let flat = abs(slopePerDay) < InsightsConfiguration.flatTrendSlopePerDayMinutes

        if flat {
            return InsightMessage(
                tone: .flat,
                text: "Your snoring looks about the same this period. Keep tracking to spot changes."
            )
        }
        if slopePerDay < 0 {
            return InsightMessage(
                tone: .trendingDown,
                text: "Your snoring is trending down. Great progress—keep it up."
            )
        }
        return InsightMessage(
            tone: .trendingUp,
            text: "Your snoring is trending up this period. Review History or try adjusting alerts."
        )
    }

    static func extremeSnoreDay(in days: [DailySnorePoint], preferMinimum: Bool) -> DailySnorePoint? {
        let withData = days.filter { $0.snoreMinutes > 0 || $0.hadSession }
        guard !withData.isEmpty else { return nil }
        return withData.min(by: { a, b in
            if a.snoreMinutes == b.snoreMinutes { return preferMinimum ? a.date < b.date : a.date > b.date }
            return preferMinimum ? a.snoreMinutes < b.snoreMinutes : a.snoreMinutes > b.snoreMinutes
        })
    }

    static func percentChange(current: Double, previous: Double) -> Double? {
        guard previous > 0.01 else { return nil }
        return ((current - previous) / previous) * 100
    }
}
