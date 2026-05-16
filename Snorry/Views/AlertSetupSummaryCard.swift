import SwiftUI
import SwiftData

// MARK: - Shared alert / notification summary (Monitor tab, Session detail, etc.)

struct AlertSetupSummaryCard: View {

    let settings: AlertSettings
    var notificationsAuthorized: Bool
    /// Short line under the title (context-specific copy).
    var caption: String
    /// Tighter padding and typography on Monitor home (saves vertical space above tab bar).
    var compact: Bool = false
    /// When true, the card can expand/collapse (Monitor home).
    var collapsible: Bool = false
    /// Initial state when `collapsible` is true.
    var startsCollapsed: Bool = true
    /// Called when the user expands or collapses (collapsible mode only).
    var onExpandedChange: ((Bool) -> Void)?

    @State private var isExpanded: Bool

    init(
        settings: AlertSettings,
        notificationsAuthorized: Bool,
        caption: String,
        compact: Bool = false,
        collapsible: Bool = false,
        startsCollapsed: Bool = true,
        onExpandedChange: ((Bool) -> Void)? = nil
    ) {
        self.settings = settings
        self.notificationsAuthorized = notificationsAuthorized
        self.caption = caption
        self.compact = compact
        self.collapsible = collapsible
        self.startsCollapsed = startsCollapsed
        self.onExpandedChange = onExpandedChange
        _isExpanded = State(initialValue: collapsible ? !startsCollapsed : true)
    }

    var body: some View {
        Group {
            if collapsible {
                collapsibleCard
            } else {
                cardContent
            }
        }
        .padding(outerPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
        )
        .onChange(of: isExpanded) { _, expanded in
            if collapsible {
                onExpandedChange?(expanded)
            }
        }
    }

    // MARK: - Collapsible (Monitor home)

    private var collapsibleCard: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            cardContent
                .padding(.top, blockSpacing)
        } label: {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                headerBlock

                if !isExpanded {
                    collapsedSummary
                }
            }
        }
        .tint(Theme.accent)
    }

    private var collapsedSummary: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(Self.oneLineSummary(settings: settings))
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(Theme.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let warning = collapsedWarningText {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: warning.icon)
                        .font(.caption2)
                        .foregroundStyle(Theme.snoring)
                    Text(warning.message)
                        .font(.caption2)
                        .foregroundStyle(Theme.snoring.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var collapsedWarningText: (icon: String, message: String)? {
        if settings.pushNotificationEnabled && !notificationsAuthorized {
            return ("exclamationmark.triangle.fill", "Enable notifications for Snorry in Settings.")
        }
        if !settings.pushNotificationEnabled && !settings.soundAlarmEnabled {
            return ("exclamationmark.circle.fill", "No alerts will fire until you enable push and/or sound.")
        }
        return nil
    }

    // MARK: - Expanded content

    private var cardContent: some View {
        let style = AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic

        return VStack(alignment: .leading, spacing: blockSpacing) {
            if !collapsible {
                headerBlock
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                summaryRow(
                    icon: "bell.badge.fill",
                    iconTint: settings.pushNotificationEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Push notifications",
                    detail: Self.pushNotificationSummary(settings: settings),
                    compact: compact
                )

                summaryRow(
                    icon: "speaker.wave.3.fill",
                    iconTint: settings.soundAlarmEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Sound alarm",
                    detail: Self.soundAlarmSummary(settings: settings),
                    compact: compact
                )
            }

            Divider()
                .background(Theme.labelTertiary.opacity(0.35))

            HStack(alignment: .top, spacing: compact ? 10 : 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(alarmIconSize)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    Text("Alarm sound")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.labelSecondary)
                    Text(style.displayName)
                        .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
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
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            Label("Alert setup", systemImage: "bell.and.waves.left.and.right")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelSecondary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.labelTertiary)
        }
    }

    private var blockSpacing: CGFloat { compact ? 8 : 14 }
    private var rowSpacing: CGFloat { compact ? 6 : 10 }
    private var outerPadding: CGFloat { compact ? 12 : 16 }
    private var alarmIconSize: Font { compact ? .title3 : .title2 }

    private func summaryRow(icon: String, iconTint: Color, title: String, detail: String, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 8 : 10) {
            Image(systemName: icon)
                .font(compact ? .callout : .body)
                .foregroundStyle(iconTint)
                .frame(width: compact ? 20 : 22, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)
                Text(detail)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(Theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private static func oneLineSummary(settings: AlertSettings) -> String {
        let push = settings.pushNotificationEnabled ? "Push on" : "Push off"
        let sound = settings.soundAlarmEnabled ? "Sound on" : "Sound off"
        let style = AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic
        return "\(push) · \(sound) · \(style.displayName)"
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
        return "On · starts after \(delay) s"
    }

    private static func alarmSoundFootnote(for style: AlarmStyle) -> String {
        if let clip = style.bundledClipName {
            return "\(clip).mp3"
        }
        return style.subtitle
    }
}
