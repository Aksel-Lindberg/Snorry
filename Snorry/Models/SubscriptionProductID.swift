import Foundation

// MARK: - App Store product identifiers (must match App Store Connect exactly)
enum SubscriptionProductID {
    static let premiumYearly = "app.Snorry.Snorry.premium.yearly"
    static let premiumMonthly = "app.Snorry.Snorry.premium.monthly"
    static let all = [premiumYearly, premiumMonthly]

    static func isPremium(_ productID: String) -> Bool {
        all.contains(productID)
    }
}

// MARK: - Paywall plan selection
enum PremiumPlan: String, CaseIterable, Identifiable {
    case yearly
    case monthly

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .yearly: SubscriptionProductID.premiumYearly
        case .monthly: SubscriptionProductID.premiumMonthly
        }
    }
}
