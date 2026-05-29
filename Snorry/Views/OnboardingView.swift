import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - First-launch onboarding (two pages: Welcome → Consent & Legal)
struct OnboardingView: View {

    /// Called after the user completes the flow so RootView can clear the gate.
    var onComplete: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var page = 0
    @State private var isRequestingPermissions = false

    /// Extra space so page dots and CTAs do not overlap on iPad.
    private var pageBottomInset: CGFloat {
        horizontalSizeClass == .regular ? 88 : 56
    }

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            TabView(selection: $page) {
                WelcomePage(
                    bottomInset: pageBottomInset,
                    onNext: { withAnimation { page = 1 } }
                )
                .tag(0)

                ConsentPage(
                    bottomInset: pageBottomInset,
                    isRequestingPermissions: $isRequestingPermissions,
                    onComplete: onComplete
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {

    var bottomInset: CGFloat
    var onNext: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero icon + wordmark
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentGradient)
                            .frame(width: 96, height: 96)
                            .shadow(color: Theme.accentGlow, radius: 24)

                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 60)

                    Text("Snorry")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.labelPrimary)

                    Text("Sleep Smarter. Snore Less.")
                        .font(Theme.handwritten(size: 18))
                        .foregroundStyle(Theme.handwrittenGradient)
                }

                // Feature cards
                VStack(spacing: 14) {
                    FeatureCard(
                        icon: "ear.fill",
                        iconColor: Theme.accent,
                        title: "Adaptive Snore Detection",
                        description: "Listens while you sleep and learns your snoring patterns. " +
                                     "All audio is processed on-device — nothing ever leaves your iPhone."
                    )

                    FeatureCard(
                        icon: "applewatch",
                        iconColor: Theme.good,
                        title: "Wrist Nudges via iOS-Compatible Smartwatch",
                        description: "Snore alerts use standard iOS notifications, which may appear " +
                                     "on your iOS-Compatible Smartwatch as a gentle haptic nudge — small enough to " +
                                     "prompt a position change without fully waking you."
                    )

                    FeatureCard(
                        icon: "bell.slash.fill",
                        iconColor: Theme.warning,
                        title: "Alerts Stop Automatically",
                        description: "The moment snoring stops, alerts cease on their own. " +
                                     "No alarm to dismiss, no disruption beyond the nudge itself."
                    )

                    FeatureCard(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: Theme.snoring,
                        title: "Track Your Progress",
                        description: "Session history and analytics show your snore patterns over time " +
                                     "and how the alert feature is affecting them — see real improvement."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                // CTA
                Button(action: onNext) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accentGradient,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, bottomInset)
            }
        }
    }
}

// MARK: - Page 2: Consent + Legal

private struct ConsentPage: View {

    var bottomInset: CGFloat
    @Binding var isRequestingPermissions: Bool
    var onComplete: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 60)

                    Text("Before You Start")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.labelPrimary)

                    Text("Snorry needs two permissions to work. Here's exactly what each one is used for.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                // Consent items
                VStack(spacing: 14) {
                    ConsentRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required to monitor breathing and detect snoring during sleep. " +
                                     "Audio is analysed locally on your iPhone and never uploaded or shared."
                    )

                    ConsentRow(
                        icon: "bell.badge.fill",
                        title: "Notifications",
                        description: "Used to send snore alerts while you sleep. Standard iOS local " +
                                     "notifications — they can appear on your iOS-Compatible Smartwatch so you get " +
                                     "wrist nudges that help you stop snoring without waking up."
                    )

                    ConsentRow(
                        icon: "chart.bar.doc.horizontal",
                        title: PrivacyCopy.onboardingAnalyticsTitle,
                        description: PrivacyCopy.usageAnalytics
                    )
                }

                // Legal card
                LegalCard()

                // Charger tip
                ChargerTipBanner()

                // Primary action
                VStack(spacing: 12) {
                    Button {
                        Task { await requestPermissions() }
                    } label: {
                        ZStack {
                            Text("Allow & Continue")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.accentGradient,
                                            in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                                .opacity(isRequestingPermissions ? 0 : 1)

                            if isRequestingPermissions {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Theme.accentGradient,
                                                in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                            }
                        }
                    }
                    .disabled(isRequestingPermissions)

                    Text("You can review and change permissions at any time in iOS Settings.")
                        .font(.caption)
                        .foregroundStyle(Theme.labelTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, bottomInset)
            }
            .padding(.horizontal, 24)
        }
    }

    // Sequentially request mic then notifications, then complete onboarding.
    private func requestPermissions() async {
        isRequestingPermissions = true
        _ = await AVAudioApplication.requestRecordPermission()
        await NotificationManager.shared.requestAuthorization()
        isRequestingPermissions = false

        let micGranted = AVAudioApplication.shared.recordPermission == .granted
        let notificationStatus = await NotificationManager.shared.checkAuthorisationStatus()
        let notificationsGranted = notificationStatus == .authorized
            || notificationStatus == .provisional
            || notificationStatus == .ephemeral
        AppAnalytics.logOnboardingCompleted(
            micGranted: micGranted,
            notificationsGranted: notificationsGranted
        )
        onComplete()
    }
}

// MARK: - Reusable sub-views

private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

private struct ConsentRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

private struct ChargerTipBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.100percent.bolt")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.good)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keep your iPhone plugged in")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Text("Snorry monitors audio all night. Connect to a charger before you fall asleep to prevent battery drain.")
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.good.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Theme.radiusCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.good.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct LegalCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legal")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelTertiary)
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 0) {
                LegalLinkRow(
                    title: "Terms of Use (EULA)",
                    destination: LegalLinks.termsOfUse
                )

                Divider()
                    .background(Theme.labelTertiary)

                LegalLinkRow(
                    title: "Privacy Policy",
                    destination: LegalLinks.privacyPolicy
                )
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        }
    }
}

private struct LegalLinkRow: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.labelTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}
