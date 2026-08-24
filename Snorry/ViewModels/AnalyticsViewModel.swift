import Foundation
import SwiftData
import Observation

// MARK: - Time window options for the analytics screen
enum AnalyticsRange: String, CaseIterable, Identifiable {
    case week        = "Week"
    case month       = "Month"
    case threeMonths = "3 Months"

    var id: String { rawValue }

    /// Rolling length used by the 3 Months window. Week and Month use calendar intervals.
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
        case .week:        return "prior week"
        case .month:       return "prior month"
        case .threeMonths: return "prior 3 months"
        }
    }

    /// Habit comparisons need more than a week of nights.
    var showsHabitCorrelation: Bool { self != .week }

    /// Calendar week/month can page; 3 Months stays a rolling 90-day window.
    var allowsPaging: Bool { self != .threeMonths }

    var pagingUnitName: String {
        switch self {
        case .week:        return "week"
        case .month:       return "month"
        case .threeMonths: return "period"
        }
    }
}

/// Inclusive start-of-day through exclusive end for one Insights window.
struct AnalyticsVisibleBounds: Equatable {
    let start: Date
    let endExclusive: Date
    /// Last start-of-day included in the dense daily series.
    let lastDayStart: Date
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
    /// True when at least one completed recording exists for this calendar day.
    /// Independent of snore minutes so a quiet night is not treated as missing.
    let hadSession: Bool

    init(date: Date, snoreMinutes: Double, eventCount: Int, hadSession: Bool = true) {
        self.date = date
        self.snoreMinutes = snoreMinutes
        self.eventCount = eventCount
        self.hadSession = hadSession
    }
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
        if abs(deltaMinutes) < InsightsConfiguration.minimumHabitDeltaMinutesForInsight {
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
    /// 0 = the period containing today; negative values move backward.
    var periodOffset: Int = 0
    var visibleBounds: AnalyticsVisibleBounds?
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
    private var oldestSessionStart: Date?

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
        Self.makeInsight(
            from: currentPeriod.dailyPoints,
            habits: habitCorrelationPoints,
            range: selectedRange
        )
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

    var canGoForward: Bool { selectedRange.allowsPaging && periodOffset < 0 }

    var canGoBack: Bool {
        Self.canPageBack(
            range: selectedRange,
            offset: periodOffset,
            now: Date(),
            oldestSession: oldestSessionStart,
            calendar: Calendar.current
        )
    }

    var periodTitle: String {
        guard let bounds = visibleBounds else { return selectedRange.rawValue }
        switch selectedRange {
        case .week:
            return periodOffset == 0 ? "This week" : Self.weekRangeLabel(from: bounds.start, through: bounds.lastDayStart)
        case .month:
            return periodOffset == 0 ? "This month" : Self.monthLabel(bounds.start)
        case .threeMonths:
            return "Last 90 days"
        }
    }

    var periodSubtitle: String? {
        guard let bounds = visibleBounds else { return nil }
        switch selectedRange {
        case .week:
            return periodOffset == 0
                ? Self.weekRangeLabel(from: bounds.start, through: bounds.lastDayStart)
                : nil
        case .month:
            return periodOffset == 0 ? Self.monthLabel(bounds.start) : nil
        case .threeMonths:
            return nil
        }
    }

    func setRange(_ range: AnalyticsRange) {
        selectedRange = range
        periodOffset = 0
        refresh()
    }

    func goToPreviousPeriod() {
        guard canGoBack else { return }
        periodOffset -= 1
        refresh()
    }

    func goToNextPeriod() {
        guard canGoForward else { return }
        periodOffset += 1
        refresh()
    }

    // MARK: Data loading

    func refresh() {
        let cal = Calendar.current
        let now = Date()
        oldestSessionStart = fetchOldestSessionStart()

        if !selectedRange.allowsPaging {
            periodOffset = 0
        }

        guard let visible = Self.visibleBounds(
            range: selectedRange,
            offset: periodOffset,
            now: now,
            calendar: cal
        ) else { return }
        visibleBounds = visible

        guard let previous = Self.previousBounds(
            before: visible.start,
            range: selectedRange,
            calendar: cal
        ) else { return }

        let fetchEnd = SleepNight.fetchEndExclusive(after: visible.endExclusive, calendar: cal)
        let sessions = fetchSessions(from: previous.start, until: fetchEnd)
        currentPeriod = Self.buildPeriodSnapshot(
            sessions: SleepNight.completedSessions(
                in: sessions,
                rangeStart: visible.start,
                rangeEnd: visible.lastDayStart,
                calendar: cal
            ),
            rangeStart: visible.start,
            rangeEnd: visible.lastDayStart,
            calendar: cal
        )
        previousPeriod = Self.buildPeriodSnapshot(
            sessions: SleepNight.completedSessions(
                in: sessions,
                rangeStart: previous.start,
                rangeEnd: previous.lastDayStart,
                calendar: cal
            ),
            rangeStart: previous.start,
            rangeEnd: previous.lastDayStart,
            calendar: cal
        )

        loadSettingsChanges(from: visible.start, until: visible.endExclusive)
        loadAlertCorrelation(
            rangeStart: visible.start,
            rangeEnd: visible.lastDayStart,
            fetchEndExclusive: fetchEnd,
            calendar: cal
        )
        loadExerciseDays(from: visible.start, until: visible.endExclusive, calendar: cal)
        loadHabitCorrelation(from: visible.start, until: visible.endExclusive, calendar: cal)
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
        visibleBounds?.start ?? Date()
    }

    var chartEndDate: Date {
        guard let bounds = visibleBounds else { return Date() }
        if periodOffset == 0 { return Date() }
        return bounds.endExclusive.addingTimeInterval(-1)
    }

    // MARK: Period bounds

    static func visibleBounds(
        range: AnalyticsRange,
        offset: Int,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsVisibleBounds? {
        let today = calendar.startOfDay(for: now)

        switch range {
        case .threeMonths:
            guard offset == 0,
                  let rawStart = calendar.date(byAdding: .day, value: -range.days, to: now) else {
                return nil
            }
            let start = calendar.startOfDay(for: rawStart)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return AnalyticsVisibleBounds(start: start, endExclusive: tomorrow, lastDayStart: today)

        case .week, .month:
            let component: Calendar.Component = range == .week ? .weekOfYear : .month
            guard let dayInPeriod = calendar.date(byAdding: component, value: offset, to: now),
                  let interval = calendar.dateInterval(of: component, for: dayInPeriod) else {
                return nil
            }
            return cappedBounds(
                start: interval.start,
                endExclusive: interval.end,
                today: today,
                calendar: calendar
            )
        }
    }

    static func previousBounds(
        before visibleStart: Date,
        range: AnalyticsRange,
        calendar: Calendar
    ) -> AnalyticsVisibleBounds? {
        switch range {
        case .week, .month:
            let component: Calendar.Component = range == .week ? .weekOfYear : .month
            guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: visibleStart),
                  let interval = calendar.dateInterval(of: component, for: dayBefore) else {
                return nil
            }
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            return AnalyticsVisibleBounds(
                start: interval.start,
                endExclusive: interval.end,
                lastDayStart: lastDay
            )
        case .threeMonths:
            let end = calendar.startOfDay(for: visibleStart)
            guard let start = calendar.date(byAdding: .day, value: -range.days, to: end) else { return nil }
            let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
            return AnalyticsVisibleBounds(start: start, endExclusive: end, lastDayStart: lastDay)
        }
    }

    static func canPageBack(
        range: AnalyticsRange,
        offset: Int,
        now: Date,
        oldestSession: Date?,
        calendar: Calendar
    ) -> Bool {
        guard range.allowsPaging, let oldestSession else { return false }
        let oldestSleepNight = SleepNight.dayStart(for: oldestSession, calendar: calendar)
        guard let visible = visibleBounds(range: range, offset: offset, now: now, calendar: calendar),
              let oldestPeriod = visibleBounds(range: range, offset: 0, now: oldestSleepNight, calendar: calendar) else {
            return false
        }
        return visible.start > oldestPeriod.start
    }

    static func weekRangeLabel(from start: Date, through end: Date) -> String {
        let startMonth = start.formatted(.dateTime.month(.abbreviated))
        let endMonth = end.formatted(.dateTime.month(.abbreviated))
        let startDay = start.formatted(.dateTime.day())
        let endDay = end.formatted(.dateTime.day())
        if startMonth == endMonth {
            return "\(startDay)–\(endDay) \(endMonth)"
        }
        return "\(startDay) \(startMonth)–\(endDay) \(endMonth)"
    }

    static func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private static func cappedBounds(
        start: Date,
        endExclusive: Date,
        today: Date,
        calendar: Calendar
    ) -> AnalyticsVisibleBounds? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let cappedEnd = min(endExclusive, tomorrow)
        guard cappedEnd > start else { return nil }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: cappedEnd) ?? start
        return AnalyticsVisibleBounds(start: start, endExclusive: cappedEnd, lastDayStart: lastDay)
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

    private func fetchOldestSessionStart() -> Date? {
        var descriptor = FetchDescriptor<SnoreSession>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.startDate
    }

    private func fetchSessions(from start: Date, until endExclusive: Date) -> [SnoreSession] {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= start },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.filter { $0.startDate < endExclusive }
    }

    private static func buildPeriodSnapshot(
        sessions: [SnoreSession],
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> PeriodSnapshot {
        let aggregated = SleepNight.aggregateByNight(sessions: sessions, calendar: calendar)
        let durationByDay = aggregated.durationByDay
        let eventsByDay = aggregated.eventsByDay
        let sessionsByDay = aggregated.sessionsByDay
        let totalSessions = sessions.count

        let threshold = InsightsConfiguration.goodNightSnoreMinutesThreshold
        var nightsUnder = 0
        for day in durationByDay.keys {
            if (durationByDay[day] ?? 0) < threshold {
                nightsUnder += 1
            }
        }

        let recordedDays = Set(sessionsByDay.keys)
        let sessionDayPoints = recordedDays.map { day in
            DailySnorePoint(
                date: day,
                snoreMinutes: durationByDay[day] ?? 0,
                eventCount: eventsByDay[day] ?? 0,
                hadSession: true
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
            recordedDays: recordedDays,
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
        recordedDays: Set<Date>,
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
                    eventCount: eventsByDay[cursor] ?? 0,
                    hadSession: recordedDays.contains(cursor)
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    private func loadSettingsChanges(from start: Date, until endExclusive: Date) {
        let descriptor = FetchDescriptor<AlertSettingsChange>(
            predicate: #Predicate { $0.timestamp >= start },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        settingsChanges = rows.filter { $0.timestamp < endExclusive }
    }

    private func loadExerciseDays(from start: Date, until endExclusive: Date, calendar: Calendar) {
        let descriptor = FetchDescriptor<MyofascialExerciseCompletion>(
            predicate: #Predicate { $0.completedAt >= start },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        exerciseLoggedDayStarts = Set(
            rows.filter { $0.completedAt < endExclusive }.map { calendar.startOfDay(for: $0.completedAt) }
        )
    }

    private func loadHabitCorrelation(from start: Date, until endExclusive: Date, calendar: Calendar) {
        let habitDescriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate { $0.dayStart >= start },
            sortBy: [SortDescriptor(\.dayStart)]
        )
        let habitLogs = ((try? context.fetch(habitDescriptor)) ?? []).filter { $0.dayStart < endExclusive }

        let exerciseDescriptor = FetchDescriptor<MyofascialExerciseCompletion>(
            predicate: #Predicate { $0.completedAt >= start },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        let exerciseRows = ((try? context.fetch(exerciseDescriptor)) ?? []).filter { $0.completedAt < endExclusive }
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

    private func loadAlertCorrelation(
        rangeStart: Date,
        rangeEnd: Date,
        fetchEndExclusive: Date,
        calendar: Calendar
    ) {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= rangeStart },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let fetched = ((try? context.fetch(descriptor)) ?? []).filter { $0.startDate < fetchEndExclusive }
        let sessions = SleepNight.completedSessions(
            in: fetched,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: calendar
        )

        let qualified = sessions.filter { s in
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

    static func makeInsight(
        from dailyPoints: [DailySnorePoint],
        habits: [HabitCorrelationPoint] = [],
        range: AnalyticsRange = .week
    ) -> InsightMessage {
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

        let tone: InsightTone
        if flat {
            tone = .flat
        } else if slopePerDay < 0 {
            tone = .trendingDown
        } else {
            tone = .trendingUp
        }

        let habit = range.showsHabitCorrelation
            ? supportingHabit(for: tone, in: habits)
            : nil
        return InsightMessage(tone: tone, text: insightText(tone: tone, habit: habit, range: range))
    }

    /// Strongest high-confidence habit that matches the trend direction.
    static func supportingHabit(
        for tone: InsightTone,
        in habits: [HabitCorrelationPoint]
    ) -> HabitCorrelationPoint? {
        let qualified = habits.filter {
            !$0.isLowConfidence &&
            abs($0.deltaMinutes) >= InsightsConfiguration.minimumHabitDeltaMinutesForInsight
        }
        guard !qualified.isEmpty else { return nil }

        switch tone {
        case .trendingUp:
            let preferred = qualified.filter {
                $0.deltaMinutes > 0 && $0.expectedEffect.typicallyAddsSnoring
            }
            let positive = qualified.filter { $0.deltaMinutes > 0 }
            let pool = preferred.isEmpty ? positive : preferred
            return pool.max(by: { $0.deltaMinutes < $1.deltaMinutes })
        case .trendingDown:
            let preferred = qualified.filter {
                $0.deltaMinutes < 0 && $0.expectedEffect == .mayHelp
            }
            let negative = qualified.filter { $0.deltaMinutes < 0 }
            let pool = preferred.isEmpty ? negative : preferred
            return pool.min(by: { $0.deltaMinutes < $1.deltaMinutes })
        case .flat:
            return qualified.max(by: { abs($0.deltaMinutes) < abs($1.deltaMinutes) })
        case .insufficientData:
            return nil
        }
    }

    /// Trend sentence plus optional habit finding. Week never quotes a delta.
    static func insightText(
        tone: InsightTone,
        habit: HabitCorrelationPoint?,
        range: AnalyticsRange
    ) -> String {
        switch tone {
        case .trendingUp:
            if let habit {
                return "Your snoring is trending up this period. Snoring ran \(habit.deltaSummary)."
            }
            if !range.showsHabitCorrelation {
                return "Your snoring is trending up this period. Review Habits or try adjusting alerts."
            }
            return "Your snoring is trending up this period. Review History or try adjusting alerts."
        case .trendingDown:
            if let habit {
                return "Your snoring is trending down. \(habit.deltaSummary). Keep it up."
            }
            return "Your snoring is trending down. Great progress—keep it up."
        case .flat:
            if let habit {
                return "Your snoring looks about the same this period. Individual nights still differ — \(habit.deltaSummary)."
            }
            if !range.showsHabitCorrelation {
                return "Your snoring looks about the same this period. Log habits to see what tracks with your nights."
            }
            return "Your snoring looks about the same this period. Keep tracking to spot changes."
        case .insufficientData:
            return "Log a few more nights to see whether your snoring is trending up or down."
        }
    }

    static func extremeSnoreDay(in days: [DailySnorePoint], preferMinimum: Bool) -> DailySnorePoint? {
        let withData = days.filter(\.hadSession)
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
