import Foundation

/// Insights KPIs and thresholds. Replace `goodNightSnoreMinutesThreshold` with Settings / AppStorage when customizable.
enum InsightsConfiguration {

    /// Nights with total daily snore below this count as a “good night” on Insights.
    static var goodNightSnoreMinutesThreshold: Double { 10 }

    /// Minimum recorded nights (including quiet 0-snore nights) before showing trend line and strong insight copy.
    static let minimumNightsForTrend = 3

    /// Snore minutes change below this (per day index) counts as “flat” trend.
    static let flatTrendSlopePerDayMinutes = 0.15

    /// Absolute habit delta below this is “about the same” and is not quoted in the trend banner.
    static let minimumHabitDeltaMinutesForInsight = 1.0
}
