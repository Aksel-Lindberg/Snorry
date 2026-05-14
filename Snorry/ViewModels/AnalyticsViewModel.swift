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

// MARK: - Analytics view model
@Observable
@MainActor
final class AnalyticsViewModel {

    var selectedRange: AnalyticsRange = .week
    var dailyPoints: [DailySnorePoint] = []
    var settingsChanges: [AlertSettingsChange] = []
    /// Per-profile snore averages for the correlation chart.
    var alertProfilePoints: [AlertProfilePoint] = []
    /// Total number of completed sessions in the current window.
    var sessionCount: Int = 0

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    // MARK: Data loading

    func refresh() {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -selectedRange.days, to: Date()) else { return }
        loadDailyPoints(since: cutoff, calendar: cal)
        loadSettingsChanges(since: cutoff)
        loadAlertCorrelation(since: cutoff)
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

    /// Earliest date shown on the X axis for the selected range.
    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
    }

    /// Mean daily snore minutes across days that have data.
    var averageDailySnoreMinutes: Double {
        guard !dailyPoints.isEmpty else { return 0 }
        return dailyPoints.map(\.snoreMinutes).reduce(0, +) / Double(dailyPoints.count)
    }

    /// Y-axis ceiling for the daily snore-minutes chart, rounded up to a clean step.
    var snoreMinutesYMax: Double {
        let peak = dailyPoints.map(\.snoreMinutes).max() ?? 0
        guard peak > 0 else { return 10 }
        let step: Double = peak < 15 ? 5 : peak < 60 ? 10 : 30
        return ceil((peak + step * 0.2) / step) * step
    }

    /// Y-axis ceiling for the daily event-count chart.
    var eventCountYMax: Double {
        let peak = Double(dailyPoints.map(\.eventCount).max() ?? 0)
        guard peak > 0 else { return 5 }
        let step: Double = peak < 10 ? 2 : peak < 30 ? 5 : 10
        return ceil((peak + step * 0.2) / step) * step
    }

    /// X-axis ceiling for the alert-correlation chart, in minutes.
    var alertChartXMax: Double {
        let peak = alertProfilePoints.map(\.avgSnoreMinutes).max() ?? 0
        guard peak > 0 else { return 10 }
        let step: Double = peak < 15 ? 5 : peak < 60 ? 10 : 30
        return ceil((peak + step * 0.2) / step) * step
    }

    // MARK: Private helpers

    private func loadDailyPoints(since cutoff: Date, calendar: Calendar) {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= cutoff },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        // Group completed sessions by start-of-day, summing duration and event count.
        var durationByDay: [Date: Double] = [:]
        var eventsByDay:   [Date: Int]    = [:]
        var totalSessions = 0
        for session in sessions where session.endDate != nil {
            let day = calendar.startOfDay(for: session.startDate)
            durationByDay[day, default: 0] += session.totalSnoreDuration / 60.0
            eventsByDay[day, default: 0]   += session.displayEventCount
            totalSessions += 1
        }

        sessionCount = totalSessions
        dailyPoints = durationByDay.keys
            .map { day in
                DailySnorePoint(date: day,
                                snoreMinutes: durationByDay[day] ?? 0,
                                eventCount: eventsByDay[day] ?? 0)
            }
            .sorted { $0.date < $1.date }
    }

    private func loadSettingsChanges(since cutoff: Date) {
        let descriptor = FetchDescriptor<AlertSettingsChange>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        settingsChanges = (try? context.fetch(descriptor)) ?? []
    }

    private func loadAlertCorrelation(since cutoff: Date) {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= cutoff },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        // Only completed sessions with a full alert snapshot qualify.
        let qualified = sessions.filter { s in
            s.endDate != nil &&
            s.snapshotPushEnabled != nil &&
            s.snapshotSoundEnabled != nil &&
            s.snapshotAlarmStyleRaw != nil
        }

        // Group by profile label, then average snore duration (minutes).
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

    /// Derives a concise profile label from snapshot flags.
    private static func profileLabel(push: Bool, sound: Bool, styleRaw: Int) -> String {
        let styleName = AlarmStyle(rawValue: styleRaw)?.displayName ?? "Sound"
        switch (push, sound) {
        case (true,  true):  return "Push · \(styleName)"
        case (true,  false): return "Push only"
        case (false, true):  return styleName
        case (false, false): return "No alerts"
        }
    }
}
