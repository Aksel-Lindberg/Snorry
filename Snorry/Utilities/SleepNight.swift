import Foundation

/// Per-night totals after bucketing completed recordings by sleep night.
struct SleepNightAggregation {
    var durationByDay: [Date: Double] = [:]
    var eventsByDay: [Date: Int] = [:]
    var sessionsByDay: [Date: [SnoreSession]] = [:]
}

/// Maps recording start times to the calendar sleep night they belong to.
enum SleepNight {

    /// Sessions starting before this hour count as the previous calendar night.
    static let morningCutoffHour = 6

    /// Start-of-day for the sleep night this recording belongs to.
    static func dayStart(for start: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: start)
        let calendarDay = calendar.startOfDay(for: start)
        if hour < morningCutoffHour,
           let previous = calendar.date(byAdding: .day, value: -1, to: calendarDay) {
            return previous
        }
        return calendarDay
    }

    /// Extend a period's exclusive end through the morning cutoff so after-midnight sessions are fetched.
    static func fetchEndExclusive(after periodEndExclusive: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: morningCutoffHour, to: periodEndExclusive)
            ?? periodEndExclusive
    }

    /// Whether a sleep night falls within an inclusive day range.
    static func isNight(
        _ night: Date,
        inRangeStart rangeStart: Date,
        through rangeEnd: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let key = calendar.startOfDay(for: night)
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)
        return key >= start && key <= end
    }

    /// Completed sessions whose sleep night lies in `[rangeStart, rangeEnd]`.
    static func completedSessions(
        in sessions: [SnoreSession],
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar = .current
    ) -> [SnoreSession] {
        sessions.filter { session in
            guard session.endDate != nil else { return false }
            let night = dayStart(for: session.startDate, calendar: calendar)
            return isNight(night, inRangeStart: rangeStart, through: rangeEnd, calendar: calendar)
        }
    }

    /// Sum minutes, events, and sessions per sleep night for completed recordings.
    static func aggregateByNight(
        sessions: [SnoreSession],
        calendar: Calendar = .current
    ) -> SleepNightAggregation {
        var aggregation = SleepNightAggregation()

        for session in sessions where session.endDate != nil {
            let night = dayStart(for: session.startDate, calendar: calendar)
            aggregation.durationByDay[night, default: 0] += session.totalSnoreDuration / 60.0
            aggregation.eventsByDay[night, default: 0] += session.displayEventCount
            aggregation.sessionsByDay[night, default: []].append(session)
        }

        for key in aggregation.sessionsByDay.keys {
            aggregation.sessionsByDay[key]?.sort { $0.startDate > $1.startDate }
        }

        return aggregation
    }
}
