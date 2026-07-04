import SwiftUI
import SwiftData

// MARK: - Alert summary values (live Settings or per-session snapshot)

struct AlertSetupDisplay {
    let pushNotificationEnabled: Bool
    let soundAlarmEnabled: Bool
    let alarmStyleRaw: Int
    let pushRepeatIntervalSeconds: Double
    let soundAlarmAfterSeconds: Double

    init(settings: AlertSettings) {
        pushNotificationEnabled = settings.pushNotificationEnabled
        soundAlarmEnabled = settings.soundAlarmEnabled
        alarmStyleRaw = settings.alarmStyleRaw
        pushRepeatIntervalSeconds = settings.pushRepeatIntervalSeconds
        soundAlarmAfterSeconds = settings.soundAlarmAfterSeconds
    }

    /// Builds from fields captured when a recording session started.
    init?(session: SnoreSession) {
        guard let push = session.snapshotPushEnabled,
              let sound = session.snapshotSoundEnabled,
              let style = session.snapshotAlarmStyleRaw else {
            return nil
        }
        pushNotificationEnabled = push
        soundAlarmEnabled = sound
        alarmStyleRaw = style
        soundAlarmAfterSeconds = session.snapshotSoundAlarmAfterSeconds ?? 10
        pushRepeatIntervalSeconds = session.snapshotPushRepeatIntervalSeconds ?? 3
    }
}

// MARK: - Shared alert / notification summary (Monitor tab, Session detail, etc.)

struct AlertSetupSummaryCard: View {

    let display: AlertSetupDisplay
    var notificationsAuthorized: Bool
    /// When true, omits live notification-permission warnings (session detail snapshot).
    var isSessionSnapshot: Bool = false
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
    /// Optional footer text link (Tonight home — e.g. open Settings).
    var footerLinkTitle: String?
    var onFooterLinkTap: (() -> Void)?

    @State private var isExpanded: Bool

    init(
        settings: AlertSettings,
        notificationsAuthorized: Bool,
        caption: String,
        compact: Bool = false,
        collapsible: Bool = false,
        startsCollapsed: Bool = true,
        onExpandedChange: ((Bool) -> Void)? = nil,
        footerLinkTitle: String? = nil,
        onFooterLinkTap: (() -> Void)? = nil
    ) {
        self.display = AlertSetupDisplay(settings: settings)
        self.notificationsAuthorized = notificationsAuthorized
        self.isSessionSnapshot = false
        self.caption = caption
        self.compact = compact
        self.collapsible = collapsible
        self.startsCollapsed = startsCollapsed
        self.onExpandedChange = onExpandedChange
        self.footerLinkTitle = footerLinkTitle
        self.onFooterLinkTap = onFooterLinkTap
        _isExpanded = State(initialValue: collapsible ? !startsCollapsed : true)
    }

    /// Session detail — nil when the session has no alert snapshot (legacy rows).
    static func forSession(_ session: SnoreSession) -> AlertSetupSummaryCard? {
        guard AlertSetupDisplay(session: session) != nil else { return nil }
        return AlertSetupSummaryCard(
            display: AlertSetupDisplay(session: session)!,
            caption: "Alert setup for this recording",
            isSessionSnapshot: true,
            collapsible: true,
            startsCollapsed: true
        )
    }

    private init(
        display: AlertSetupDisplay,
        caption: String,
        isSessionSnapshot: Bool,
        collapsible: Bool = false,
        startsCollapsed: Bool = true
    ) {
        self.display = display
        self.notificationsAuthorized = false
        self.isSessionSnapshot = isSessionSnapshot
        self.caption = caption
        self.compact = false
        self.collapsible = collapsible
        self.startsCollapsed = startsCollapsed
        self.onExpandedChange = nil
        self.footerLinkTitle = nil
        self.onFooterLinkTap = nil
        _isExpanded = State(initialValue: collapsible ? !startsCollapsed : true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if collapsible {
                    collapsibleCard
                } else {
                    cardContent
                }
            }

            if let footerLinkTitle, let onFooterLinkTap {
                Button(action: onFooterLinkTap) {
                    CardFooterTextLink(title: footerLinkTitle)
                }
                .buttonStyle(.plain)
                .padding(.top, compact ? 8 : 10)
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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                        headerBlock

                        if !isExpanded {
                            collapsedSummary
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Alert setup")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse alert details" : "Expand alert details")

            if isExpanded {
                cardContent
                    .padding(.top, blockSpacing)
            }
        }
    }

    private var collapsedSummary: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(Self.oneLineSummary(display: display))
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
        if !isSessionSnapshot,
           display.pushNotificationEnabled,
           !notificationsAuthorized {
            return ("exclamationmark.triangle.fill", "Enable notifications for Snorry in Settings.")
        }
        if !display.pushNotificationEnabled, !display.soundAlarmEnabled {
            let message = isSessionSnapshot
                ? "No push or sound alerts were enabled for this recording."
                : "No alerts will fire until you enable push and/or sound."
            return ("exclamationmark.circle.fill", message)
        }
        return nil
    }

    // MARK: - Expanded content

    private var cardContent: some View {
        let style = AlarmStyle(rawValue: display.alarmStyleRaw) ?? .classic

        return VStack(alignment: .leading, spacing: blockSpacing) {
            if !collapsible {
                headerBlock
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                summaryRow(
                    icon: "bell.badge.fill",
                    iconTint: display.pushNotificationEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Push notifications",
                    detail: Self.pushNotificationSummary(display: display),
                    compact: compact
                )

                summaryRow(
                    icon: "speaker.wave.3.fill",
                    iconTint: display.soundAlarmEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Sound alarm",
                    detail: Self.soundAlarmSummary(display: display),
                    compact: compact
                )
            }

            if display.soundAlarmEnabled {
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
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(Theme.labelOnSurfaceSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !isSessionSnapshot,
               display.pushNotificationEnabled,
               !notificationsAuthorized {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.snoring)
                    Text("Turn on notifications for Snorry in Settings so pushes can appear.")
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(Theme.snoring.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !display.pushNotificationEnabled, !display.soundAlarmEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.snoring)
                    Text(
                        isSessionSnapshot
                            ? "No push or sound alerts were enabled for this recording."
                            : "No alerts will fire until you enable push and/or sound in Settings."
                    )
                        .font(compact ? .caption2 : .caption)
                        .foregroundStyle(Theme.snoring.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            Label("Alert setup", systemImage: "bell.and.waves.left.and.right")
                .font(compact ? .caption.bold() : .subheadline.bold())
                .foregroundStyle(Theme.labelPrimary)
            Text(caption)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
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
                    .font(compact ? .caption.bold() : .subheadline.weight(.semibold))
                    .foregroundStyle(compact ? Theme.labelSecondary : Theme.labelPrimary)
                Text(detail)
                    .font(compact ? .caption2 : .footnote)
                    .foregroundStyle(Theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private static func oneLineSummary(display: AlertSetupDisplay) -> String {
        let push = display.pushNotificationEnabled ? "Push on" : "Push off"
        let sound = display.soundAlarmEnabled ? "Sound on" : "Sound off"
        guard display.soundAlarmEnabled else {
            return "\(push) · \(sound)"
        }
        let style = AlarmStyle(rawValue: display.alarmStyleRaw) ?? .classic
        return "\(push) · \(sound) · \(style.displayName)"
    }

    private static func pushNotificationSummary(display: AlertSetupDisplay) -> String {
        guard display.pushNotificationEnabled else {
            return "Off"
        }
        let repeatEvery = Int(display.pushRepeatIntervalSeconds)
        return "On · first push after 2 s of snoring · repeats every \(repeatEvery) s"
    }

    private static func soundAlarmSummary(display: AlertSetupDisplay) -> String {
        guard display.soundAlarmEnabled else {
            return "Off"
        }
        let delay = Int(display.soundAlarmAfterSeconds)
        return "On · starts after \(delay) s"
    }

    private static func alarmSoundFootnote(for style: AlarmStyle) -> String {
        if let clip = style.bundledClipName {
            return "\(clip).mp3"
        }
        return style.subtitle
    }
}

// MARK: - Card footer link (Tonight home shortcuts)

struct CardFooterTextLink: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
