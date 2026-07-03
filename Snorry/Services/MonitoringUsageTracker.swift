import Foundation

// MARK: - Free-tier monitoring start limit (10 sessions before paywall; 30 in Debug)
enum MonitoringUsageTracker {

    static var freeLimit: Int {
        #if DEBUG
        30
        #else
        10
        #endif
    }

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
