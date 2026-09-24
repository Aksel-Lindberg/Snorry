import SwiftUI
import SwiftData

// MARK: - Alert summary values (live Settings or per-session snapshot)

struct AlertSetupDisplay {
    let pushNotificationEnabled: Bool
    let soundAlarmEnabled: Bool
    let alarmStyleRaw: Int

    init(settings: AlertSettings) {
        pushNotificationEnabled = settings.pushNotificationEnabled
        soundAlarmEnabled = settings.soundAlarmEnabled
        alarmStyleRaw = settings.alarmStyleRaw
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
    /// Optional footer text link (Tonight home — e.g. open Settings).
    var footerLinkTitle: String?
    var onFooterLinkTap: (() -> Void)?

    init(
        settings: AlertSettings,
        notificationsAuthorized: Bool,
        caption: String,
        compact: Bool = false,
        footerLinkTitle: String? = nil,
        onFooterLinkTap: (() -> Void)? = nil
    ) {
        self.display = AlertSetupDisplay(settings: settings)
        self.notificationsAuthorized = notificationsAuthorized
        self.isSessionSnapshot = false
        self.caption = caption
        self.compact = compact
        self.footerLinkTitle = footerLinkTitle
        self.onFooterLinkTap = onFooterLinkTap
    }

    /// Session detail — nil when the session has no alert snapshot (legacy rows).
    static func forSession(_ session: SnoreSession) -> AlertSetupSummaryCard? {
        guard let display = AlertSetupDisplay(session: session) else { return nil }
        return AlertSetupSummaryCard(
            display: display,
            caption: "Alert setup for this recording",
            isSessionSnapshot: true
        )
    }

    private init(
        display: AlertSetupDisplay,
        caption: String,
        isSessionSnapshot: Bool
    ) {
        self.display = display
        self.notificationsAuthorized = false
        self.isSessionSnapshot = isSessionSnapshot
        self.caption = caption
        self.compact = false
        self.footerLinkTitle = nil
        self.onFooterLinkTap = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryContent

            if let footerLinkTitle, let onFooterLinkTap {
                Button(action: onFooterLinkTap) {
                    CardFooterTextLink(title: footerLinkTitle)
                }
                .buttonStyle(.plain)
                .padding(.top, compact ? 8 : 10)
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
        )
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            headerBlock

            Text(Self.oneLineSummary(display: display))
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(Theme.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let warning = warningText {
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

    private var warningText: (icon: String, message: String)? {
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

    private var outerPadding: CGFloat { compact ? 12 : 16 }

    private static func oneLineSummary(display: AlertSetupDisplay) -> String {
        let push = display.pushNotificationEnabled ? "Push on" : "Push off"
        let sound = display.soundAlarmEnabled ? "Sound on" : "Sound off"
        guard display.soundAlarmEnabled else {
            return "\(push) · \(sound)"
        }
        let style = AlarmStyle(rawValue: display.alarmStyleRaw) ?? .classic
        return "\(push) · \(sound) · \(style.displayName)"
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
