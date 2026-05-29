import SwiftUI

// MARK: - Help & How-To (Monitor tab toolbar sheet)

struct HelpCenterView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// One section open at a time keeps the page scannable on iPhone.
    @State private var openSection: HelpSection?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        introHero

                        helpAccordion(
                            section: .gettingStarted,
                            title: "First launch & privacy",
                            subtitle: "Onboarding, microphone, notifications, analytics, legal",
                            systemImage: "sparkles"
                        ) {
                            HelpBullet(
                                icon: "hand.wave.fill",
                                title: "Welcome flow",
                                detail: "First launch is a two-page onboarding flow: Welcome, then Before You Start (microphone + notifications explained, legal links, charger tip). Tap Allow & Continue to request iOS permissions and reach the main tabs."
                            )
                            HelpBullet(
                                icon: "mic.fill",
                                title: "Microphone",
                                detail: "Snorry analyses audio on-device to detect snoring-like patterns. Monitoring cannot run without access—if permission is still pending or denied, the Monitor tab shows a short prompt; undetermined access opens a permissions sheet when you tap Start."
                            )
                            HelpBullet(
                                icon: "bell.badge.fill",
                                title: "Notifications",
                                detail: "Snore alerts use standard local notifications on this iPhone (they can mirror to a paired watch like any iOS alert). Onboarding requests notification permission together with the microphone; later you can enable or disable push alerts in Settings."
                            )
                            HelpBullet(
                                icon: "chart.bar.doc.horizontal",
                                title: "Usage analytics",
                                detail: PrivacyCopy.usageAnalytics
                            )
                        }

                        helpAccordion(
                            section: .tabBar,
                            title: "Bottom navigation",
                            subtitle: "Four tabs — Monitor, History, Analytics, Settings",
                            systemImage: "square.grid.2x2.fill"
                        ) {
                            tabChip(icon: "waveform", name: "Monitor", hint: "Start sessions and see your latest summary.")
                            tabChip(icon: "clock.arrow.circlepath", name: "History", hint: "Browse past nights and open session details.")
                            tabChip(icon: "chart.line.uptrend.xyaxis", name: "Analytics", hint: "Trends, charts, and how settings relate to snore duration.")
                            tabChip(icon: "gearshape", name: "Settings", hint: "Alert channels and timings, alarm style, support, reset/delete logs, and legal links.")
                        }

                        helpAccordion(
                            section: .monitorHome,
                            title: "Monitor tab (home)",
                            subtitle: "Start control, alert summary, last session",
                            systemImage: "waveform"
                        ) {
                            HelpBullet(
                                icon: "play.circle.fill",
                                title: "Start monitoring",
                                detail: "Tap the large sleep animation (moon and waves) to begin. If the microphone is not yet allowed, a permissions sheet appears first; if iOS access was denied, the same tap opens the system Settings app so you can enable the mic."
                            )
                            HelpBullet(
                                icon: "slider.horizontal.3",
                                title: "Alert setup summary",
                                detail: "The card mirrors your saved choices: push on/off, sound alarm on/off, fixed 2 s push delay, your sound-alarm delay, and repeat-push interval (1–10 s) when push is enabled—exactly what Settings will apply to the next session."
                            )
                            HelpBullet(
                                icon: "clock.fill",
                                title: "Last Session",
                                detail: "When you have completed nights, the card summarises the most recent session: sleep duration, snore event count, and total snore time (counts confirmed snoring, not other sound categories)."
                            )
                            HelpBullet(
                                icon: "lock.fill",
                                title: "Overnight & locked iPhone",
                                detail: "Start monitoring, then lock your phone. Background audio keeps capture running for that session. While locked, Snorry uses a lighter-weight detection path; after you stop, it may re-classify saved clips so History labels stay trustworthy."
                            )
                            HelpBullet(
                                icon: "applewatch",
                                title: "Apple Watch",
                                detail: "Snorry is iPhone-only. Snore alerts are local notifications; they can mirror to your watch if iPhone alerts mirror to Apple Watch. " +
                                    "There is no watchOS app—wrist delivery is not guaranteed."
                            )
                        }

                        helpAccordion(
                            section: .monitorLive,
                            title: "Live monitoring screen",
                            subtitle: "Spectrum, metrics, alerts, timeline",
                            systemImage: "dot.radiowaves.left.and.right"
                        ) {
                            HelpBullet(
                                icon: "circle.fill",
                                title: "Status",
                                detail: "The badge steps through Quiet, Detecting Pattern…, then Snoring Detected once a bout is confirmed. Push and sound alarms only arm after confirmation so a single stray noise does not wake you."
                            )
                            HelpBullet(
                                icon: "chart.xyaxis.line",
                                title: "Live power spectrum",
                                detail: "Log-scaled band energy from 45 Hz up to the Nyquist frequency; red highlights mark the breath-tempo harmonic when a bout is confirmed—same idea as the rumble marker stored on each event."
                            )
                            HelpBullet(
                                icon: "lungs.fill",
                                title: "dBFS, BRPM, Events",
                                detail: "dBFS shows input loudness (— when extremely quiet). BRPM appears once tempo is estimated for the current bout. Events counts completed snore bouts, not every classifier frame."
                            )
                            HelpBullet(
                                icon: "bell.and.waves.left.and.right.fill",
                                title: "Alert phases",
                                detail: "When enabled in Settings, you’ll see in-app states such as “Push notification sent”, “Alarm active” (tone ramps in steps), and “Alert cleared” when snoring has stopped long enough. On a locked phone the sound alarm stops automatically after five seconds so it does not drone indefinitely; silence thresholds also relax while locked so alerts can clear."
                            )
                            HelpBullet(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Live timeline",
                                detail: "Charts roughly the last ten minutes of loudness with snoring stretches emphasised so you can see recent dynamics at a glance."
                            )
                            HelpBullet(
                                icon: "stop.circle.fill",
                                title: "Stop monitoring",
                                detail: "Tears down audio, saves the session to Sleep History, and dismisses this screen. A short overlay can appear while clips finish encoding; if the night included locked or background recording, you may briefly see a “classifying sounds” step before returning home."
                            )
                        }

                        helpAccordion(
                            section: .history,
                            title: "History tab",
                            subtitle: "Sleep History list & session detail",
                            systemImage: "clock.arrow.circlepath"
                        ) {
                            HelpBullet(
                                icon: "list.bullet",
                                title: "Session rows",
                                detail: "The tab is titled Sleep History. Each row shows the session start, sleep duration, snoring event count, total snore time, and a bar scaled to the longest snore-duration night currently in the list."
                            )
                            HelpBullet(
                                icon: "hand.draw.fill",
                                title: "Swipe to delete",
                                detail: "Swipe left on a row to delete that night’s session, waveform samples, and clips from storage."
                            )
                            HelpBullet(
                                icon: "chevron.right.circle.fill",
                                title: "Session detail",
                                detail: "Shows duration stats, Snore Clock (snoring bouts only), a Session Timeline chart from saved waveform samples, and a Sound Events list. After nights with background recording, each event may be labelled Snoring, Sleep Talking, or Environment; tap a row with playback available to hear its AAC clip."
                            )
                        }

                        helpAccordion(
                            section: .analytics,
                            title: "Analytics tab",
                            subtitle: "Ranges, trends, settings markers",
                            systemImage: "chart.line.uptrend.xyaxis"
                        ) {
                            HelpBullet(
                                icon: "calendar",
                                title: "Time range",
                                detail: "Pick week, month, or three months to focus the charts and summary pills."
                            )
                            HelpBullet(
                                icon: "timer",
                                title: "Summary pills",
                                detail: "Avg min/day (snore time), session count, and distinct days with data in the selected window."
                            )
                            HelpBullet(
                                icon: "chart.bar.fill",
                                title: "Snore duration trend",
                                detail: "The Snore duration card plots daily snore minutes and event counts for the selected window, with optional numbered markers when alert settings were saved."
                            )
                            HelpBullet(
                                icon: "mappin.and.ellipse",
                                title: "Settings change markers",
                                detail: "Expand the legend under the chart to read each saved change; you can also remove individual markers from analytics without touching your current Settings values."
                            )
                            HelpBullet(
                                icon: "chart.bar.xaxis",
                                title: "Alert type vs snore duration",
                                detail: "The Alert Type vs Snore duration card averages snore minutes per alert configuration profile in the period—the footer reminds you this is correlation, not causation or medical advice."
                            )
                        }

                        helpAccordion(
                            section: .settings,
                            title: "Settings tab",
                            subtitle: "Alerts, sound, support, data & legal",
                            systemImage: "gearshape.fill"
                        ) {
                            HelpBullet(
                                icon: "bell.badge.fill",
                                title: "Alert channels",
                                detail: "Turn on push notifications, the in-app sound alarm, or both. With both enabled, push is sent first, then the tone after your chosen sound delay. While a push alert is active and snoring continues, Snorry can repeat the notification on the interval you set (1–10 s)."
                            )
                            HelpBullet(
                                icon: "timer",
                                title: "Alert timings",
                                detail: "Push is sent after a fixed 2 s of continuous snoring. The sound alarm fires after the delay you choose on its slider. Alerts clear once snoring has stayed off for a few seconds (timing adapts slightly if the phone is locked during the session)."
                            )
                            HelpBullet(
                                icon: "speaker.wave.3.fill",
                                title: "Alarm style",
                                detail: "Pick the alarm character you notice best and use Play / Stop to preview the selected style."
                            )
                            HelpBullet(
                                icon: "lifepreserver.fill",
                                title: "Support",
                                detail: "Open Support for contact options and common troubleshooting topics."
                            )
                            HelpBullet(
                                icon: "arrow.counterclockwise",
                                title: "Reset & delete logs",
                                detail: "Reset to Defaults recreates alert preferences. Delete All Sleep & Settings Logs removes every session, clip, waveform, and analytics marker row—you must stop monitoring first or Snorry will show an error. Your current on-screen Settings values are not reverted by delete."
                            )
                            HelpBullet(
                                icon: "doc.text.fill",
                                title: "Legal",
                                detail: "Terms of Use and Privacy Policy links open in Safari."
                            )
                            HelpBullet(
                                icon: "xmark.circle.fill",
                                title: "Cancel / Save",
                                detail: "Cancel reloads the last saved values; Save persists changes and posts them to the next monitoring session (and to the summary cards on Monitor and session detail)."
                            )
                        }

                        tipFooter
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 18)
                    .padding(.vertical, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .clearsFloatingTabBar()
            }
            .navigationTitle("Help & How-To")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onAppear {
            if openSection == nil { openSection = .gettingStarted }
        }
    }

    // MARK: - Sections

    private enum HelpSection: String, CaseIterable, Identifiable {
        case gettingStarted, tabBar, monitorHome, monitorLive, history, analytics, settings
        var id: String { rawValue }
    }

    private func binding(for section: HelpSection) -> Binding<Bool> {
        Binding(
            get: { openSection == section },
            set: { isOn in
                if isOn {
                    openSection = section
                } else if openSection == section {
                    openSection = nil
                }
            }
        )
    }

    private var introHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snorry at a glance")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.labelPrimary)
                    Text("Sleep Snore Alert & Tracking")
                        .font(.subheadline)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }

            Text(
                "Use the accordions below to explore each tab and screen. Tap a row to expand it; " +
                "opening another section collapses the previous one so the guide stays easy to read."
            )
            .font(.footnote)
            .foregroundStyle(Theme.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard)
                        .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func helpAccordion(
        section: HelpSection,
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: binding(for: section)) {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 12)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(Theme.labelPrimary)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.labelTertiary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            .tint(Theme.accent)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private func tabChip(icon: String, name: String, hint: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.snoring)
                .frame(width: 26, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var tipFooter: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(Theme.good.opacity(0.9))
                .font(.title3)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("A note on wellness")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                Text(
                    "Snorry helps you notice patterns overnight. It does not replace medical advice—speak with " +
                    "a clinician if you have concerns about sleep apnoea or breathing."
                )
                .font(.caption)
                .foregroundStyle(Theme.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

// MARK: - Bullet row

private struct HelpBullet: View {

    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent.opacity(0.95))
                .frame(width: 26, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
    }
}
