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
    /// Average snore percentage across all completed sessions that day (0–100).
    let snorePercent: Double
}

// MARK: - Analytics view model
@Observable
@MainActor
final class AnalyticsViewModel {

    var selectedRange: AnalyticsRange = .week
    var dailyPoints: [DailySnorePoint] = []
    var settingsChanges: [AlertSettingsChange] = []
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
    }

    // MARK: Computed chart helpers

    /// Earliest date shown on the X axis for the selected range.
    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date()) ?? Date()
    }

    /// Average snore % across all daily points in the window.
    var averageSnorePercent: Double {
        guard !dailyPoints.isEmpty else { return 0 }
        return dailyPoints.map(\.snorePercent).reduce(0, +) / Double(dailyPoints.count)
    }

    /// Y-axis ceiling: rounds up to the nearest 25 % above the peak, minimum 25.
    var yAxisMax: Double {
        let peak = dailyPoints.map(\.snorePercent).max() ?? 0
        guard peak > 0 else { return 100 }
        return min(100, ceil((peak + 5) / 25) * 25)
    }

    // MARK: Private helpers

    private func loadDailyPoints(since cutoff: Date, calendar: Calendar) {
        let descriptor = FetchDescriptor<SnoreSession>(
            predicate: #Predicate { $0.startDate >= cutoff },
            sortBy: [SortDescriptor(\.startDate)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []

        // Group completed sessions by start-of-day and collect snore fractions
        var grouped: [Date: [Double]] = [:]
        for session in sessions where session.endDate != nil {
            let day = calendar.startOfDay(for: session.startDate)
            grouped[day, default: []].append(session.snoreFraction * 100)
        }

        sessionCount = grouped.values.reduce(0) { $0 + $1.count }
        dailyPoints = grouped
            .map { day, values in
                DailySnorePoint(date: day,
                                snorePercent: values.reduce(0, +) / Double(values.count))
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
}
