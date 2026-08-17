import Foundation
import SwiftData

// MARK: - One logged habit for a calendar night
@Model
final class HabitLog {

    /// Matches `HabitKind.rawValue`.
    var habitID: String
    /// Start of the calendar night this habit applies to.
    var dayStart: Date
    var loggedAt: Date

    init(habitID: String, dayStart: Date, loggedAt: Date = Date()) {
        self.habitID = habitID
        self.dayStart = dayStart
        self.loggedAt = loggedAt
    }
}

extension HabitLog {

    /// Logs for one calendar day, keyed by habit id.
    static func logs(
        for dayStart: Date,
        in all: [HabitLog],
        calendar: Calendar = .current
    ) -> [String: HabitLog] {
        let key = calendar.startOfDay(for: dayStart)
        var map: [String: HabitLog] = [:]
        for log in all where calendar.isDate(log.dayStart, inSameDayAs: key) {
            map[log.habitID] = log
        }
        return map
    }

    static func isLogged(
        habit: HabitKind,
        on dayStart: Date,
        in all: [HabitLog],
        calendar: Calendar = .current
    ) -> Bool {
        logs(for: dayStart, in: all, calendar: calendar)[habit.id] != nil
    }

    /// Calendar days with at least one habit log in range.
    static func loggedDayStarts(
        in all: [HabitLog],
        since cutoff: Date,
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(
            all
                .filter { $0.dayStart >= cutoff }
                .map { calendar.startOfDay(for: $0.dayStart) }
        )
    }

    /// Day starts where a specific habit was logged.
    static func loggedDayStarts(
        for habit: HabitKind,
        in all: [HabitLog],
        since cutoff: Date,
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(
            all
                .filter { $0.habitID == habit.id && $0.dayStart >= cutoff }
                .map { calendar.startOfDay(for: $0.dayStart) }
        )
    }
}
