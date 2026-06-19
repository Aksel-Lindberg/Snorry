import SwiftUI

// MARK: - Support page
struct SupportView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    contactCard
                    commonTopicsCard
                    troubleshootingCard
                    privacyCard
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 30 : 18)
                .padding(.vertical, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: horizontalSizeClass == .regular ? 760 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .clearsFloatingTabBar()
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Snorry Support", systemImage: "lifepreserver.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)

            Text("Need help with monitoring, alerts, logs, or playback? You can find quick answers below and contact support anytime.")
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

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact Support")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            Link(destination: URL(string: "mailto:\(LegalLinks.supportEmail)")!) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Theme.accent)
                    Text(LegalLinks.supportEmail)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(Theme.labelTertiary)
                }
                .padding(12)
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Text("Include your iPhone model, iOS version, app version, and a short issue description for faster support.")
                .font(.caption)
                .foregroundStyle(Theme.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var commonTopicsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common Help Topics")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            supportBullet(
                icon: "mic.fill",
                title: "Microphone Permission",
                detail: "Snorry needs microphone access to detect snoring. Enable it in iPhone Settings > Privacy & Security > Microphone."
            )
            supportBullet(
                icon: "bell.badge.fill",
                title: "Notifications Not Showing",
                detail: "Enable notifications in iPhone Settings > Notifications > Snorry, then verify Push Notifications are enabled in app Settings."
            )
            supportBullet(
                icon: "trash.fill",
                title: "Delete Logs",
                detail: "Use Settings > Delete All Sleep & Settings Logs to permanently remove saved sessions, snore events, and settings-change history."
            )
            supportBullet(
                icon: "waveform",
                title: "Audio Clips",
                detail: "Snore clips are stored locally on your device and used for session review features."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var troubleshootingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Troubleshooting")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            supportStep(number: "1", text: "Close and reopen Snorry.")
            supportStep(number: "2", text: "Restart your iPhone.")
            supportStep(number: "3", text: "Update to the latest app version.")
            supportStep(number: "4", text: "If still unresolved, contact support by email.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            Text(PrivacyCopy.supportPrivacySummary)
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private func supportBullet(icon: String, title: String, detail: String) -> some View {
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

    private func supportStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(Theme.monoDigit(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
