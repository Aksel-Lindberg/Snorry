import AppTrackingTransparency
import FacebookCore

/// Meta App Events wrapper — gated on the same ATT / debug rules as Firebase.
enum MetaAnalytics {

    /// Applies initial collection settings after the Meta SDK launches.
    static func configureAfterSDKLaunch() {
        syncCollectionWithATT()
    }

    /// Keeps Meta auto-logging and advertiser settings aligned with ATT resolution.
    static func syncCollectionWithATT() {
        let collectionEnabled = TrackingAuthorizationManager.isAnalyticsCollectionEnabled
        #if DEBUG
        let trackingAuthorized = collectionEnabled
        #else
        let trackingAuthorized = ATTrackingManager.trackingAuthorizationStatus == .authorized
        #endif

        Settings.shared.isAdvertiserTrackingEnabled = trackingAuthorized
        Settings.shared.isAutoLogAppEventsEnabled = collectionEnabled
        Settings.shared.isAdvertiserIDCollectionEnabled = collectionEnabled
    }

    // MARK: - Standard events

    static func logCompletedRegistration() {
        guard TrackingAuthorizationManager.isAnalyticsCollectionEnabled else { return }
        AppEvents.shared.logEvent(.completedRegistration)
    }

    static func logViewedContent(source: String?) {
        guard TrackingAuthorizationManager.isAnalyticsCollectionEnabled else { return }
        AppEvents.shared.logEvent(
            .viewedContent,
            parameters: [
                .contentType: "paywall",
                .contentID: source ?? "default"
            ]
        )
    }
}
