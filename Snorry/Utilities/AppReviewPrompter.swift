import StoreKit
import UIKit

/// Requests an App Store review after meaningful engagement — once per install.
@MainActor
enum AppReviewPrompter {

    private static let completedReplayCountKey = "completedSnoreClipReplayCount"
    private static let hasRequestedReviewKey = "hasRequestedAppStoreReview"

    private static let replaysBeforePrompt = 2

    /// In-memory flag set when the replay threshold is reached; consumed on session detail dismiss.
    private static var pendingReviewAfterSessionDetail = false

    /// Call when a snore clip finishes playing in session detail.
    static func recordCompletedSnoreClipReplay() {
        guard !UserDefaults.standard.bool(forKey: hasRequestedReviewKey) else { return }

        let count = UserDefaults.standard.integer(forKey: completedReplayCountKey) + 1
        UserDefaults.standard.set(count, forKey: completedReplayCountKey)

        if count >= replaysBeforePrompt {
            pendingReviewAfterSessionDetail = true
        }
    }

    /// Prompt when leaving session detail so replay isn't interrupted mid-clip.
    static func requestReviewIfPendingAfterSessionDetail() {
        guard pendingReviewAfterSessionDetail else { return }
        pendingReviewAfterSessionDetail = false

        guard !UserDefaults.standard.bool(forKey: hasRequestedReviewKey) else { return }
        UserDefaults.standard.set(true, forKey: hasRequestedReviewKey)

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        SKStoreReviewController.requestReview(in: scene)
    }
}
