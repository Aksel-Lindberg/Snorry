import Foundation

// MARK: - Canonical legal URLs shared by OnboardingView and SettingsView
enum LegalLinks {
    static let termsOfUse   = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://snorry.lintech.no/privacy-policy/")!
    static let support = URL(string: "https://snorry.lintech.no/support/")!
    static let supportEmail = "Support@lintech.no"
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

// MARK: - In-app privacy copy (sleep data vs Firebase usage analytics)
enum PrivacyCopy {
    /// Shown on Support and onboarding — sleep/session data stays on the device.
    static let onDeviceSleepData =
        "Sleep sessions, snore clips, and waveforms are processed and stored on your iPhone. " +
        "They are not uploaded for cloud storage or analysis."

    /// Firebase Analytics and Meta App Events — non-health usage events only; gated by App Tracking Transparency in Release.
    static let usageAnalytics =
        "Snorry may send anonymous app usage data (such as screens visited and feature use) to " +
        "Google Firebase Analytics and Meta App Events to improve the app and measure marketing performance. " +
        "Sleep audio and health session content are not included. " +
        "On first launch, iOS asks for tracking permission via App Tracking Transparency before analytics are collected."

    static var supportPrivacySummary: String {
        onDeviceSleepData + " " + usageAnalytics + " See the Privacy Policy in Settings > Legal for details."
    }

    static let onboardingAnalyticsTitle = "Usage analytics"
}
