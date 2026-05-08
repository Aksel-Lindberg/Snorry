import SwiftUI

// MARK: - Help & How-To (presented from Monitor home)

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
                            subtitle: "Onboarding, microphone, and notifications",
                            systemImage: "sparkles"
                        ) {
                            HelpBullet(
                                icon: "hand.wave.fill",
                                title: "Welcome flow",
                                detail: "The first time you open Snorry, you’ll see a short introduction and consent step. Complete it to reach the main tabs."
                            )
                            HelpBullet(
                                icon: "mic.fill",
                                title: "Microphone",
                                detail: "Snorry listens for audio patterns associated with snoring. Without microphone access, monitoring cannot run—you’ll see a prompt on the Monitor tab."
                            )
                            HelpBullet(
                                icon: "bell.badge.fill",
                                title: "Notifications",
                                detail: "Optional alerts use local notifications on this iPhone. You can refine behaviour later under Settings."
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
                            tabChip(icon: "chart.line.uptrend.xyaxis", name: "Analytics", hint: "Trends, charts, and how settings relate to snore percentage.")
                            tabChip(icon: "gearshape.fill", name: "Settings", hint: "Alerts, timings, alarm style, volume, and legal links.")
                        }

                        helpAccordion(
                            section: .monitorHome,
                            title: "Monitor tab (home)",
                            subtitle: "Start button, alert summary, last session",
                            systemImage: "waveform"
                        ) {
                            HelpBullet(
                                icon: "play.circle.fill",
                                title: "Start monitoring",
                                detail: "Tap the animated moon control to begin. If permission is needed, Snorry walks you through microphone access first."
                            )
                            HelpBullet(
                                icon: "slider.horizontal.3",
                                title: "Alert setup summary",
                                detail: "The card shows push vs sound alarm choices and timings that will apply to your next session—aligned with Settings."
                            )
                            HelpBullet(
                                icon: "clock.fill",
                                title: "Last Session",
                                detail: "Quick stats from your most recent night: duration, snore events, breathing rate (BRPM) average, and snoring percentage."
                            )
                            HelpBullet(
                                icon: "applewatch",
                                title: "Apple Watch",
                                detail: "Pair your watch for wrist alerts—Snorry is built to complement phone notifications when you wear it overnight."
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
                                detail: "Quiet → detecting pattern → snoring detected. Colours mirror calm vs attention vs active snoring."
                            )
                            HelpBullet(
                                icon: "chart.xyaxis.line",
                                title: "Live power spectrum",
                                detail: "Shows frequency energy while you sleep; harmonic emphasis helps highlight breath-related rhythm when snoring is confirmed."
                            )
                            HelpBullet(
                                icon: "lungs.fill",
                                title: "dBFS, BRPM, Events",
                                detail: "Approximate loudness, estimated breaths per minute when available, and a running count of snore-related events."
                            )
                            HelpBullet(
                                icon: "bell.and.waves.left.and.right.fill",
                                title: "Alert phases",
                                detail: "When thresholds are met, you may see push notification and/or in-app alarm phases depending on Settings—until snoring clears."
                            )
                            HelpBullet(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Live timeline",
                                detail: "A rolling view of recent audio activity so you can see how the night evolves."
                            )
                            HelpBullet(
                                icon: "stop.circle.fill",
                                title: "Stop monitoring",
                                detail: "Ends the session, saves results to History, and returns you to the Monitor home."
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
                                detail: "Each row shows date, duration, event count, and snoring percentage with a compact visual bar."
                            )
                            HelpBullet(
                                icon: "hand.draw.fill",
                                title: "Swipe to delete",
                                detail: "Remove a session you no longer need. This frees storage used by that night’s data."
                            )
                            HelpBullet(
                                icon: "chevron.right.circle.fill",
                                title: "Session detail",
                                detail: "Opens stats, Snore Clock (when events exist), session timeline chart, and a list of events—tap an event to replay its clip when audio was captured."
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
                                icon: "percent",
                                title: "Summary pills",
                                detail: "Average snore percentage, number of sessions, and days with data in the selected window."
                            )
                            HelpBullet(
                                icon: "chart.area.fill",
                                title: "Snore percentage trend",
                                detail: "Daily averages plotted over time so you can spot improvement or rough patches."
                            )
                            HelpBullet(
                                icon: "mappin.and.ellipse",
                                title: "Settings change markers",
                                detail: "When you save Push or Alarm settings, numbered markers can appear on the chart—expand the legend to see what changed and when."
                            )
                            HelpBullet(
                                icon: "chart.bar.xaxis",
                                title: "Alert type vs snore %",
                                detail: "Compares average snoring under different alert configurations in the period—useful context, not a medical diagnosis."
                            )
                        }

                        helpAccordion(
                            section: .settings,
                            title: "Settings tab",
                            subtitle: "Alerts, sound, data & legal",
                            systemImage: "gearshape.fill"
                        ) {
                            HelpBullet(
                                icon: "bell.badge.fill",
                                title: "Alert channels",
                                detail: "Enable push notifications on this iPhone, sound alarm in the app, or both. Repeat interval adjusts how often push can remind you."
                            )
                            HelpBullet(
                                icon: "timer",
                                title: "Alert timings",
                                detail: "Push fires after a short fixed delay; sound alarm delay is configurable. Alerts ease when snoring stops."
                            )
                            HelpBullet(
                                icon: "speaker.wave.3.fill",
                                title: "Alarm style & volume",
                                detail: "Choose a tone character you notice easily; preview with Play/Stop. Master volume affects alarms and previews."
                            )
                            HelpBullet(
                                icon: "arrow.counterclockwise",
                                title: "Reset & delete logs",
                                detail: "Reset restores defaults. Delete All removes saved sessions and analytics history—your current slider values stay until you change them."
                            )
                            HelpBullet(
                                icon: "doc.text.fill",
                                title: "Legal",
                                detail: "Terms and Privacy open in Safari so you can review policies anytime."
                            )
                            HelpBullet(
                                icon: "xmark.circle.fill",
                                title: "Cancel / Save",
                                detail: "Cancel discards edits this visit; Save writes alert preferences for upcoming nights."
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
                    Text("Sleep snore alerts & gentle tracking")
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
