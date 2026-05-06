import SwiftUI
import SwiftData

// MARK: - Shared alert / notification summary (Monitor tab, Session detail, etc.)

struct AlertSetupSummaryCard: View {

    let settings: AlertSettings
    var notificationsAuthorized: Bool
    /// Short line under the title (context-specific copy).
    var caption: String

    var body: some View {
        let style = AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Alert setup", systemImage: "bell.and.waves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(
                    icon: "bell.badge.fill",
                    iconTint: settings.pushNotificationEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Push notifications",
                    detail: Self.pushNotificationSummary(settings: settings)
                )

                summaryRow(
                    icon: "speaker.wave.3.fill",
                    iconTint: settings.soundAlarmEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Sound alarm",
                    detail: Self.soundAlarmSummary(settings: settings)
                )
            }

            Divider()
                .background(Theme.labelTertiary.opacity(0.35))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Alarm sound")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.labelSecondary)
                    Text(style.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.labelPrimary)
                    Text(Self.alarmSoundFootnote(for: style))
                        .font(.caption2)
                        .foregroundStyle(Theme.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .opacity(settings.soundAlarmEnabled ? 1 : 0.45)

            if settings.pushNotificationEnabled && !notificationsAuthorized {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.snoring)
                    Text("Turn on notifications for Snorry in Settings so pushes can appear.")
                        .font(.caption2)
                        .foregroundStyle(Theme.snoring.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !settings.pushNotificationEnabled && !settings.soundAlarmEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.snoring)
                    Text("No alerts will fire until you enable push and/or sound in Settings.")
                        .font(.caption2)
                        .foregroundStyle(Theme.snoring.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
        )
    }

    private func summaryRow(icon: String, iconTint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconTint)
                .frame(width: 22, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private static func pushNotificationSummary(settings: AlertSettings) -> String {
        guard settings.pushNotificationEnabled else {
            return "Off"
        }
        let repeatEvery = Int(settings.pushRepeatIntervalSeconds)
        return "On · first push after 2 s of snoring · repeats every \(repeatEvery) s"
    }

    private static func soundAlarmSummary(settings: AlertSettings) -> String {
        guard settings.soundAlarmEnabled else {
            return "Off"
        }
        let delay = Int(settings.soundAlarmAfterSeconds)
        let pct = Int((settings.alarmVolume * 100).rounded())
        return "On · starts after \(delay) s · volume \(pct)%"
    }

    private static func alarmSoundFootnote(for style: AlarmStyle) -> String {
        if let clip = style.bundledClipName {
            return "\(clip).mp3"
        }
        return style.subtitle
    }
}
