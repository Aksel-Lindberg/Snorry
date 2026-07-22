import Foundation
import SwiftData

// MARK: - Logged completion for a myofascial exercise
@Model
final class MyofascialExerciseCompletion {

    var exerciseID: String
    var completedAt: Date

    init(exerciseID: String, completedAt: Date = Date()) {
        self.exerciseID = exerciseID
        self.completedAt = completedAt
    }
}

extension MyofascialExerciseCompletion {

    /// One column in the rolling 7-day strip (start-of-day, oldest → newest).
    struct WeekdayStripItem: Identifiable {
        let id: Date
        let dayStart: Date
        let isToday: Bool
        let isCompleted: Bool
    }

    static func completions(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion]
    ) -> [MyofascialExerciseCompletion] {
        all.filter { $0.exerciseID == exercise.id }
            .sorted { $0.completedAt > $1.completedAt }
    }

    static func hasCompletionToday(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> Bool {
        all.contains {
            $0.exerciseID == exercise.id && calendar.isDateInToday($0.completedAt)
        }
    }

    /// Calendar days (start of day) with at least one log for this exercise.
    static func completedDayStarts(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(
            all
                .filter { $0.exerciseID == exercise.id }
                .map { calendar.startOfDay(for: $0.completedAt) }
        )
    }

    /// Last seven calendar days ending today, with completion flags.
    static func lastSevenStripItems(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> [WeekdayStripItem] {
        let completed = completedDayStarts(for: exercise, in: all, calendar: calendar)
        let todayStart = calendar.startOfDay(for: Date())

        return (0..<7).reversed().compactMap { daysAgo -> WeekdayStripItem? in
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) else {
                return nil
            }
            let dayStart = calendar.startOfDay(for: day)
            return WeekdayStripItem(
                id: dayStart,
                dayStart: dayStart,
                isToday: daysAgo == 0,
                isCompleted: completed.contains(dayStart)
            )
        }
    }

    /// Consecutive completed days counting backward from today (or yesterday if today open).
    static func currentStreak(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> Int {
        let completed = completedDayStarts(for: exercise, in: all, calendar: calendar)
        guard !completed.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: Date())

        if !completed.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = calendar.startOfDay(for: yesterday)
        }

        while completed.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: previous)
        }
        return streak
    }

    /// Unique completion days, newest first (for history UI).
    static func uniqueSortedDays(
        from completions: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> [Date] {
        let days = Set(completions.map { calendar.startOfDay(for: $0.completedAt) })
        return days.sorted(by: >)
    }

    /// Distinct calendar days logged (one count per day even if multiple rows exist).
    static func loggedDayCount(
        from completions: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> Int {
        uniqueSortedDays(from: completions, calendar: calendar).count
    }
}
