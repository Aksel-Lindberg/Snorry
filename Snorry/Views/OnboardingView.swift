import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - First-launch onboarding (two pages: Name intro → Consent & Legal)
struct OnboardingView: View {

    /// Called after the user completes the flow so RootView can clear the gate.
    var onComplete: () -> Void

    @AppStorage(UserPreferences.displayNameKey) private var userDisplayName = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var page = 0
    @State private var isRequestingPermissions = false
    @State private var draftName = ""

    /// Extra space so page dots and CTAs do not overlap on iPad.
    private var pageBottomInset: CGFloat {
        horizontalSizeClass == .regular ? 88 : 56
    }

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            TabView(selection: $page) {
                NameIntroPage(
                    draftName: $draftName,
                    bottomInset: pageBottomInset,
                    onContinue: saveNameAndAdvance,
                    onSkip: { withAnimation { page = 1 } }
                )
                .tag(0)

                ConsentPage(
                    displayName: userDisplayName,
                    bottomInset: pageBottomInset,
                    isRequestingPermissions: $isRequestingPermissions,
                    onComplete: onComplete
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .onAppear {
            draftName = userDisplayName
        }
    }

    private func saveNameAndAdvance() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        userDisplayName = trimmed
        withAnimation { page = 1 }
    }
}

// MARK: - Page 1: Name intro

private struct NameIntroPage: View {

    @Binding var draftName: String
    @FocusState private var isNameFieldFocused: Bool
    var bottomInset: CGFloat
    var onContinue: () -> Void
    var onSkip: () -> Void

    private var canSaveName: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Image("HomeAppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Theme.accentGlow, radius: 24)
                    .accessibilityLabel("Snorry")
                    .padding(.top, 60)

                Text("Welcome to Snorry")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.labelPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Text("Your smart snore companion")
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("What's your name?")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 36)

                TextField("Your name", text: $draftName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(Theme.labelPrimary)
                    .focused($isNameFieldFocused)
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .submitLabel(.continue)
                    .onSubmit {
                        dismissKeyboard()
                        if canSaveName { onContinue() }
                    }

                VStack(spacing: 12) {
                    Button {
                        dismissKeyboard()
                        onContinue()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accentGradient,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                    }
                    .disabled(!canSaveName)
                    .opacity(canSaveName ? 1 : 0.45)

                    Button {
                        dismissKeyboard()
                        onSkip()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.labelSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, bottomInset)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func dismissKeyboard() {
        isNameFieldFocused = false
    }
}

// MARK: - Page 2: Consent + Legal

private struct ConsentPage: View {

    let displayName: String
    var bottomInset: CGFloat
    @Binding var isRequestingPermissions: Bool
    var onComplete: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentGradient)
                            .frame(width: 96, height: 96)
                            .shadow(color: Theme.accentGlow, radius: 24)

                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 60)

                    Text(UserPreferences.welcomeGreeting(displayName: displayName))
                        .font(.title2.bold())
                        .foregroundStyle(Theme.labelPrimary)
                        .multilineTextAlignment(.center)

                    Text("Before you start")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .multilineTextAlignment(.center)

                    Text("Snorry needs two permissions to work. Here's exactly what each one is used for.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }

                VStack(spacing: 14) {
                    ConsentRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required to listen for snoring during sleep. " +
                                     "Audio is analyzed locally on your iPhone and never uploaded or shared."
                    )

                    ConsentRow(
                        icon: "bell.badge.fill",
                        title: "Notifications",
                        description: "Used to send snore alerts while you sleep. Standard iOS local " +
                                     "notifications — they can mirror to your paired watch (including Apple Watch) " +
                                     "so you get Snore alerts on your wrist. There is no watchOS app."
                    )
                }

                LegalCard()
                ChargerTipBanner()

                VStack(spacing: 12) {
                    Button {
                        Task { await requestPermissions() }
                    } label: {
                        ZStack {
                            Text("Continue")
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
                        .foregroundStyle(Theme.labelSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, bottomInset)
            }
            .padding(.horizontal, 24)
        }
    }

    // ATT first, then mic and notifications, then complete onboarding.
    private func requestPermissions() async {
        isRequestingPermissions = true
        await TrackingAuthorizationManager.requestTrackingAuthorizationIfNeeded()
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
                Text("Snorry records audio all night. Connect to a charger before you fall asleep to prevent battery drain.")
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
                .foregroundStyle(Theme.labelSecondary)
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
