import FirebaseAnalytics
import StoreKit

/// Firebase Analytics wrapper — distinct from the in-app Insights tab (sleep trends).
enum AppAnalytics {

    static func log(_ name: String, _ params: [String: Any]? = nil) {
        guard TrackingAuthorizationManager.isAnalyticsCollectionEnabled else { return }
        Analytics.logEvent(name, parameters: params)
    }

    // MARK: - Onboarding

    static func logOnboardingCompleted(micGranted: Bool, notificationsGranted: Bool) {
        log("onboarding_completed", [
            "mic_granted": micGranted,
            "notifications_granted": notificationsGranted
        ])
        MetaAnalytics.logCompletedRegistration()
    }

    // MARK: - Monitoring

    static func logMonitoringStarted(pushEnabled: Bool, soundEnabled: Bool) {
        log("monitoring_started", [
            "push_enabled": pushEnabled,
            "alarm_mode": alarmMode(pushEnabled: pushEnabled, soundEnabled: soundEnabled)
        ])
    }

    static func logMonitoringStopped(durationSeconds: Int) {
        log("monitoring_stopped", [
            "duration_bucket": durationBucket(for: durationSeconds)
        ])
    }

    // MARK: - Settings

    static func logSettingsSaved(changes: SettingsChangeFlags) {
        var params: [String: Any] = [:]
        if changes.pushEnabled { params["push_enabled_changed"] = true }
        if changes.soundAlarmEnabled { params["sound_alarm_changed"] = true }
        if changes.alarmTone { params["alert_tone_changed"] = true }
        guard !params.isEmpty else { return }
        log("settings_saved", params)
    }

    // MARK: - Navigation

    static func logTabSelected(_ tab: String) {
        log("tab_selected", ["tab": tab])
    }

    // MARK: - Subscriptions

    static func logPaywallViewed(source: String? = nil) {
        var params: [String: Any] = [:]
        if let source { params["source"] = source }
        log("paywall_viewed", params.isEmpty ? nil : params)
        MetaAnalytics.logViewedContent(source: source)
    }

    static func logPurchaseStarted(product: Product) {
        log("purchase_started")
        MetaAnalytics.logInitiatedCheckout(product: product)
    }

    static func logPurchaseCompleted(product: Product, transaction: Transaction) {
        log("purchase_completed")
        MetaAnalytics.logSubscriptionSuccess(product: product, transaction: transaction)
    }

    static func logRestoreTapped() {
        log("restore_tapped")
    }

    static func logSnoreClipShared() {
        log("snore_clip_shared")
    }

    // MARK: - Cross-promotion

    static func logSleepAllyPromoOpened(source: String) {
        log("sleepally_promo_opened", ["source": source])
    }

    static func logSleepAllyAppStoreTapped(source: String) {
        log("sleepally_app_store_tapped", ["source": source])
    }

    // MARK: - Helpers

    private static func alarmMode(pushEnabled: Bool, soundEnabled: Bool) -> String {
        switch (pushEnabled, soundEnabled) {
        case (true, true): return "push_and_sound"
        case (true, false): return "push_only"
        case (false, true): return "sound_only"
        case (false, false): return "none"
        }
    }

    private static func durationBucket(for seconds: Int) -> String {
        switch seconds {
        case ..<1800: return "0_30m"
        case 1800..<7200: return "30m_2h"
        default: return "2h_plus"
        }
    }
}

/// Non-PII flags for which settings categories changed on save.
struct SettingsChangeFlags {
    var pushEnabled = false
    var soundAlarmEnabled = false
    var alarmTone = false
}
