import AppTrackingTransparency
import FirebaseAnalytics

/// Gates Firebase Analytics on App Tracking Transparency (Release) or the debug launch flag (Debug).
@MainActor
enum TrackingAuthorizationManager {

    #if DEBUG
    private static var isFirebaseAnalyticsDebugMode: Bool {
        CommandLine.arguments.contains("-FIRAnalyticsDebugEnabled")
    }
    #endif

    /// Mirrors whether `AppAnalytics.log` should emit events.
    static var isAnalyticsCollectionEnabled: Bool {
        #if DEBUG
        isFirebaseAnalyticsDebugMode
        #else
        ATTrackingManager.trackingAuthorizationStatus == .authorized
        #endif
    }

    /// Applies the current ATT status to Firebase Analytics collection (Release only).
    static func syncAnalyticsCollectionWithATT() {
        #if DEBUG
        Analytics.setAnalyticsCollectionEnabled(isFirebaseAnalyticsDebugMode)
        #else
        Analytics.setAnalyticsCollectionEnabled(
            ATTrackingManager.trackingAuthorizationStatus == .authorized
        )
        #endif
    }

    /// Presents the system ATT dialog when status is `.notDetermined`, then syncs Firebase.
    static func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            syncAnalyticsCollectionWithATT()
            return
        }
        await ATTrackingManager.requestTrackingAuthorization()
        syncAnalyticsCollectionWithATT()
    }
}
