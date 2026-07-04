import SwiftUI
import UIKit

// MARK: - SleepAlly cross-promotion detail page
struct SleepAllyPromoView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    contextCard
                    featuresCard
                    disclaimerCard
                    appStoreButton
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 30 : 18)
                .padding(.vertical, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: horizontalSizeClass == .regular ? 760 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .clearsFloatingTabBar()
        }
        .navigationTitle("SleepAlly")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            AppAnalytics.logSleepAllyPromoOpened(source: "settings")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("SleepAlly", systemImage: "moon.stars.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text(
                "Understand your nights with fall-asleep audio, wake-up alarms, snore awareness, "
                    + "and habit tracking — all on your iPhone."
            )
                .font(.footnote)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.accent.opacity(0.20), lineWidth: 1)
        )
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From the makers of Snorry")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            Text(
                "Snorry is built for simple snore recording and alerts. SleepAlly adds a fuller "
                    + "bedtime routine: calming audio (including YouTube tracks), customizable alarms, "
                    + "Snore Stop nudges for earbuds, a habits diary, charts, and AI chat for patterns."
            )
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you get")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            featureBullet(
                icon: "waveform.badge.magnifyingglass",
                title: "On-device snore awareness",
                detail: "Detect and log snoring during a night session, review events, and see trends over time."
            )
            featureBullet(
                icon: "music.note",
                title: "Fall-asleep audio",
                detail: "Calming sounds or your chosen YouTube track with fade and timing to match your routine."
            )
            featureBullet(
                icon: "alarm.fill",
                title: "Wake-up alarm",
                detail: "Set an alarm and choose audio you like, including YouTube sources where supported."
            )
            featureBullet(
                icon: "hand.tap.fill",
                title: "Snore Stop nudges",
                detail: "Gentle haptic-style reminders when snoring is ongoing — haptic, sound, or music escalation."
            )
            featureBullet(
                icon: "book.fill",
                title: "Habits and diary",
                detail: "Log food, medication, mood, and more to relate daily choices to how you sleep and snore."
            )
            featureBullet(
                icon: "lock.shield.fill",
                title: "Privacy-first",
                detail: "Core sleep, snore, and habit data stays on your device."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var disclaimerCard: some View {
        Text("SleepAlly is a wellness companion, not a medical device. Free on the App Store.")
            .font(.caption)
            .foregroundStyle(Theme.labelOnSurfaceSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var appStoreButton: some View {
        Button {
            AppAnalytics.logSleepAllyAppStoreTapped(source: "promo_page")
            UIApplication.shared.open(LegalLinks.sleepAllyAppStore)
        } label: {
            HStack(spacing: 8) {
                Text("View on App Store")
                    .font(.headline)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        }
        .buttonStyle(.plain)
    }

    private func featureBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
