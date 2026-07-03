import Foundation

// MARK: - Free-tier monitoring start limit (20 sessions before paywall)
enum MonitoringUsageTracker {

    static let freeLimit = 20

    private static let countKey = "freeMonitoringStartCount"

    static var startCount: Int {
        UserDefaults.standard.integer(forKey: countKey)
    }

    static var remainingFreeStarts: Int {
        max(0, freeLimit - startCount)
    }

    static func canStartMonitoring(hasPremium: Bool) -> Bool {
        hasPremium || startCount < freeLimit
    }

    static func recordMonitoringStart(hasPremium: Bool) {
        guard !hasPremium else { return }
        UserDefaults.standard.set(startCount + 1, forKey: countKey)
    }
}
