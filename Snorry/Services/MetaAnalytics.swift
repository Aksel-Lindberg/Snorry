import AppTrackingTransparency
import FacebookCore
import StoreKit

/// Meta App Events wrapper — gated on the same ATT / debug rules as Firebase.
enum MetaAnalytics {

    private static var wasCollectionEnabled = false
    private static var pendingActivateAfterSDKInit = false
    private static var hasInitializedSDK = false

    /// Syncs Meta consent flags before SDK initialization. Returns whether collection newly became enabled.
    @discardableResult
    static func syncCollectionWithATT() -> Bool {
        let collectionEnabled = TrackingAuthorizationManager.isAnalyticsCollectionEnabled
        #if DEBUG
        let trackingAuthorized = collectionEnabled
        #else
        let trackingAuthorized = ATTrackingManager.trackingAuthorizationStatus == .authorized
        #endif

        Settings.shared.isAdvertiserTrackingEnabled = trackingAuthorized
        Settings.shared.isAutoLogAppEventsEnabled = collectionEnabled
        Settings.shared.isAdvertiserIDCollectionEnabled = collectionEnabled

        let becameEnabled = collectionEnabled && !wasCollectionEnabled
        wasCollectionEnabled = collectionEnabled

        if becameEnabled {
            if hasInitializedSDK {
                AppEvents.shared.activateApp()
            } else {
                pendingActivateAfterSDKInit = true
            }
        }

        return becameEnabled
    }

    /// Call after `ApplicationDelegate.shared.application(...)` on launch.
    static func completeSDKInitialization() {
        hasInitializedSDK = true
        guard pendingActivateAfterSDKInit else { return }
        pendingActivateAfterSDKInit = false
        AppEvents.shared.activateApp()
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
            parameters: subscriptionParameters(for: nil, contentID: paywallContentID(source: source))
        )
    }

    static func logInitiatedCheckout(product: Product) {
        guard TrackingAuthorizationManager.isAnalyticsCollectionEnabled else { return }
        AppEvents.shared.logEvent(
            .initiatedCheckout,
            parameters: subscriptionParameters(for: product, contentID: product.id)
        )
    }

    static func logSubscriptionSuccess(product: Product, transaction: Transaction) {
        guard TrackingAuthorizationManager.isAnalyticsCollectionEnabled else { return }

        if transaction.offerType == .introductory {
            AppEvents.shared.logEvent(
                .startTrial,
                parameters: subscriptionParameters(for: product, contentID: product.id)
            )
        } else {
            logSubscribe(product: product)
        }
    }

    // MARK: - Helpers

    private static func logSubscribe(product: Product) {
        AppEvents.shared.logEvent(
            .subscribe,
            valueToSum: priceAmount(for: product),
            parameters: subscriptionParameters(for: product, contentID: product.id)
        )
    }

    private static func paywallContentID(source: String?) -> String {
        guard let source, !source.isEmpty else { return "paywall_default" }
        if source.hasPrefix("paywall_") { return source }
        return "paywall_\(source)"
    }

    private static func subscriptionParameters(
        for product: Product?,
        contentID: String
    ) -> [AppEvents.ParameterName: Any] {
        var params: [AppEvents.ParameterName: Any] = [
            .contentID: contentID,
            .contentType: "subscription"
        ]
        if let product {
            params[.currency] = currencyCode(for: product)
        }
        return params
    }

    private static func currencyCode(for product: Product) -> String {
        // Product.price is denominated in the App Store storefront currency for this user.
        Locale.current.currency?.identifier ?? "USD"
    }

    private static func priceAmount(for product: Product) -> Double {
        NSDecimalNumber(decimal: product.price).doubleValue
    }
}
