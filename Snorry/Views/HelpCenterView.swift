import SwiftUI

// MARK: - Help & How-To (Tonight tab toolbar sheet)

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

                        howSnorryWorksCard

                        helpAccordion(
                            section: .gettingStarted,
                            title: "First launch & privacy",
                            subtitle: "Onboarding, microphone, notifications, usage analytics, legal",
                            systemImage: "sparkles"
                        ) {
                            HelpBullet(
                                icon: "hand.wave.fill",
                                title: "Welcome flow",
                                detail: "First launch is a two-page onboarding flow: a short name intro (optional), then Before you start (microphone + notifications explained, legal links, charger tip). Tap Continue to request iOS permissions and reach the main tabs. See How Snorry works below for what the app does."
                            )
                            HelpBullet(
                                icon: "mic.fill",
                                title: "Microphone",
                                detail: "Snorry analyzes audio on-device to detect snoring-like patterns. Recording cannot run without access—if permission is still pending or denied, the Tonight tab shows a short prompt; undetermined access opens a permissions sheet when you tap Start."
                            )
                            HelpBullet(
                                icon: "bell.badge.fill",
                                title: "Notifications",
                                detail: "Snore alerts use standard local notifications on this iPhone (they can mirror to your paired watch like any iOS alert). Onboarding requests notification permission together with the microphone; later you can enable or disable push notifications in Settings."
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
                            subtitle: "Four tabs — Tonight, History, Insights, Exercises",
                            systemImage: "square.grid.2x2.fill"
                        ) {
                            tabChip(icon: "moon.stars.fill", name: "Tonight", hint: "Start recording and see your latest summary. Settings and Help are in the top-right toolbar.")
                            tabChip(icon: "clock.arrow.circlepath", name: "History", hint: "Browse past nights and open session details.")
                            tabChip(icon: "chart.line.uptrend.xyaxis", name: "Insights", hint: "Trends, charts, and how settings relate to snore duration.")
                            tabChip(icon: "figure.mind.and.body", name: "Exercises", hint: "Myofascial exercise guides with completion tracking.")
                        }

                        helpAccordion(
                            section: .monitorHome,
                            title: "Tonight tab (home)",
                            subtitle: "Start control, alert summary, last session",
                            systemImage: "moon.stars.fill"
                        ) {
                            HelpBullet(
                                icon: "play.circle.fill",
                                title: "Start recording",
                                detail: "Tap the large sleep animation (moon and waves) to begin. If the microphone is not yet allowed, a permissions sheet appears first; if iOS access was denied, the same tap opens the system Settings app so you can enable the mic."
                            )
                            HelpBullet(
                                icon: "questionmark.circle",
                                title: "Help & Settings (toolbar)",
                                detail: "Top right on Tonight: the question mark opens this Help & How-To guide; the gear opens app Settings (alerts, alarm style, Premium, support, and data controls) in a sheet."
                            )
                            HelpBullet(
                                icon: "slider.horizontal.3",
                                title: "Alert setup summary",
                                detail: "The card mirrors your saved choices: push on/off, sound alarm on/off, and alarm style. Alert timing is fixed in the app—push after 2 s of snoring, sound after 5 s, clear after 3 s of silence. When both channels are on, push and sound repeat together on the same pulse. Tap Change in Settings on the card to open the gear sheet."
                            )
                            HelpBullet(
                                icon: "clock.fill",
                                title: "Last Session",
                                detail: "When you have completed nights, the card summarizes the most recent session: sleep duration, snore event count, and total snore time (counts confirmed snoring, not other sound categories). Before your first completed night, the card shows placeholders and “No recordings yet.” Tap View details to open the full session screen."
                            )
                            HelpBullet(
                                icon: "star.circle.fill",
                                title: "Free vs Premium",
                                detail: "Free includes up to 20 recording sessions and your latest sleep session in History. Snorry Premium unlocks unlimited recording, full Sleep History, and Insights. A remaining-session count appears under Start when you are on the free plan; upgrade from the Settings sheet (gear on Tonight) or when a limit is reached."
                            )
                            HelpBullet(
                                icon: "applewatch",
                                title: "Apple Watch",
                                detail: "Snorry is iPhone-only. Snore alerts are local notifications; they can mirror to your paired watch (including Apple Watch) if iPhone alerts mirror to the watch. " +
                                    "There is no watchOS app—wrist delivery is not guaranteed."
                            )
                        }

                        helpAccordion(
                            section: .monitorLive,
                            title: "Live recording session",
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
                                detail: "Log-scaled band energy from 45 Hz up to the Nyquist frequency. Bars brighten when snoring is confirmed."
                            )
                            HelpBullet(
                                icon: "speaker.wave.2.fill",
                                title: "dBFS & Events",
                                detail: "dBFS shows input loudness (— when extremely quiet). Events counts completed snore bouts, not every classifier frame."
                            )
                            HelpBullet(
                                icon: "bell.and.waves.left.and.right.fill",
                                title: "Alert phases",
                                detail: "When push is enabled, an in-app card confirms “Push notification sent” while the alert is active. When the sound alarm is enabled, built-in tones and short clips play as bursts with a 3 s pause between repeats; song tracks loop continuously. Alerts keep going until snoring has stopped for several seconds—not when a single logged bout ends. Volume starts at 13% of max, then rises in 25% steps to full level while snoring continues (every burst for tones and short clips, or every 3 s for song tracks). The recording screen shows the current alarm volume %. With both on, push and sound fire on the same pulse after the sound alarm starts at 5 s. Alerts clear once snoring has stayed off for about 3 s after the last detected snore (timing adapts slightly if the phone is locked during the session)."
                            )
                            HelpBullet(
                                icon: "chart.line.uptrend.xyaxis",
                                title: "Live timeline",
                                detail: "Charts roughly the last ten minutes of loudness with snoring stretches emphasized so you can see recent dynamics at a glance."
                            )
                            HelpBullet(
                                icon: "stop.circle.fill",
                                title: "Stop recording",
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
                                detail: "Shows duration stats, Snore Clock (snoring bouts only), alert setup used for that recording, a Session Timeline chart from saved waveform samples, and a Sound Events list. Each event is labeled Snoring, Sleep Talking, or Environment; background nights classify non-snore sounds more often."
                            )
                            HelpBullet(
                                icon: "play.circle.fill",
                                title: "Event playback",
                                detail: "In Sound Events, tap the play button on any row with a saved AAC clip to hear that bout. Rows without a clip file show a dimmed control—usually when encoding failed or the bout was too short to store."
                            )
                            HelpBullet(
                                icon: "square.and.arrow.up",
                                title: "Share event clips",
                                detail: "Tap the share icon on any Sound Events row that has playback. iOS opens the standard share sheet so you can AirDrop, Messages, Mail, or save the file. Snorry exports a single .m4a clip named with the event time—only that bout is shared, not your full night."
                            )
                            HelpBullet(
                                icon: "lock.fill",
                                title: "Premium & older sessions",
                                detail: "On the free plan, only your most recent sleep session opens in detail; older rows appear locked until you upgrade to Premium. Your data is kept on device—Premium simply unlocks browsing the full list."
                            )
                        }

                        helpAccordion(
                            section: .analytics,
                            title: "Insights tab",
                            subtitle: "Ranges, trends, settings markers (Premium)",
                            systemImage: "chart.line.uptrend.xyaxis"
                        ) {
                            HelpBullet(
                                icon: "star.circle.fill",
                                title: "Premium feature",
                                detail: "Insights requires Snorry Premium. Free users see an upgrade prompt; subscribers get trend charts, summary pills, and alert-correlation views described below."
                            )
                            HelpBullet(
                                icon: "calendar",
                                title: "Time range",
                                detail: "Pick Week, Month, or 3 Months to focus the charts and summary pills."
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
                                detail: "Expand the legend under the chart to read each saved change (push on/off, sound on/off, or alarm style). You can also remove individual markers from Insights without touching your current Settings values."
                            )
                            HelpBullet(
                                icon: "chart.bar.xaxis",
                                title: "Alert type vs snore duration",
                                detail: "The Alert Type vs Snore duration card averages snore minutes per alert configuration profile in the period—the footer reminds you this is correlation, not causation or medical advice."
                            )
                        }

                        helpAccordion(
                            section: .exercises,
                            title: "Exercises tab",
                            subtitle: "Myofascial exercises, zoomable guides, completion log",
                            systemImage: "figure.mind.and.body"
                        ) {
                            HelpBullet(
                                icon: "list.bullet.rectangle",
                                title: "Exercise library",
                                detail: "The Exercises tab lists guided myofascial exercises in order—from tongue posture awareness through strength drills. Each card shows the full infographic, title, and a short description."
                            )
                            HelpBullet(
                                icon: "arrow.up.left.and.arrow.down.right",
                                title: "Read & zoom images",
                                detail: "Tap any exercise image to open it full screen. Double-tap to zoom in or out; pinch to resize and drag to pan when zoomed so small text is easier to read."
                            )
                            HelpBullet(
                                icon: "checkmark.circle.fill",
                                title: "Log completion",
                                detail: "Tap the checkmark on a card when you finish that exercise for the day. Snorry records one entry per calendar day—tapping again the same day shows a brief “Already logged for today” message."
                            )
                            HelpBullet(
                                icon: "calendar",
                                title: "Completion history",
                                detail: "Tap the calendar control to see every date you logged that exercise, newest first. Swipe left on a date to remove a mistaken entry."
                            )
                        }

                        helpAccordion(
                            section: .settings,
                            title: "Settings",
                            subtitle: "Open from the gear on Tonight — alerts, alarm style, support, data & legal",
                            systemImage: "gearshape.fill"
                        ) {
                            HelpBullet(
                                icon: "bell.badge.fill",
                                title: "Alert channels",
                                detail: "Turn on push notifications, the in-app sound alarm, or both—there are no timing sliders. Push-only sends notifications; sound-only plays tone bursts; with both on, push starts after 2 s of snoring and the tone joins after 5 s, then push and sound repeat together on the same pulse until snoring stops."
                            )
                            HelpBullet(
                                icon: "timer",
                                title: "When alerts fire",
                                detail: "Timing is fixed: first push after 2 s of continuous snoring, sound alarm after 5 s, and alerts clear after about 3 s without snoring. On a locked phone, confirmation and alert delays use a slightly faster profile so alerts still reach you reliably."
                            )
                            HelpBullet(
                                icon: "speaker.wave.3.fill",
                                title: "Alarm style",
                                detail: "Pick the alarm character you notice best and use Play / Stop to preview the selected style. Built-in tones and short clips play as bursts with a 3 s pause during live alerts; song tracks loop continuously with volume stepping every 3 s. Burst length for tones and short clips also paces repeated push alerts when snoring continues."
                            )
                            HelpBullet(
                                icon: "star.circle.fill",
                                title: "Snorry Premium",
                                detail: "Shows Free or Premium status. Upgrade for unlimited recording, full Sleep History, and Insights; manage billing through your Apple ID subscriptions."
                            )
                            HelpBullet(
                                icon: "lifepreserver.fill",
                                title: "Support",
                                detail: "Open Support for contact options and common troubleshooting topics."
                            )
                            HelpBullet(
                                icon: "arrow.counterclockwise",
                                title: "Reset & delete logs",
                                detail: "Reset to Defaults restores push/sound toggles and alarm style. Delete All Sleep & Settings Logs removes every sleep session, snore clip, waveform, and Insights settings-change marker—you must stop recording first or Snorry will show an error. Your current on-screen Settings values are not reverted by delete."
                            )
                            HelpBullet(
                                icon: "doc.text.fill",
                                title: "Legal",
                                detail: "Terms of Use and Privacy Policy links open in Safari."
                            )
                            HelpBullet(
                                icon: "xmark.circle.fill",
                                title: "Cancel / Save",
                                detail: "Cancel reloads the last saved values; Save persists changes and posts them to the next recording session (and to the summary cards on Tonight and session detail)."
                            )
                        }

                        overnightTipsCard
                        earbudPartnerTipsCard
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if openSection == nil { openSection = .gettingStarted }
        }
    }

    // MARK: - Sections

    private enum HelpSection: String, CaseIterable, Identifiable {
        case gettingStarted, tabBar, monitorHome, monitorLive, history, analytics, exercises, settings
        var id: String { rawValue }
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
            .foregroundStyle(Theme.labelSecondary)
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
        let isExpanded = openSection == section

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    openSection = isExpanded ? nil : section
                }
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
                            .foregroundStyle(Theme.labelSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 12)
            }
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

    private var howSnorryWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .symbolRenderingMode(.hierarchical)
                Text("How Snorry works")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
            }

            VStack(spacing: 14) {
                HowSnorryWorksFeatureRow(
                    icon: "ear.fill",
                    iconColor: Theme.accent,
                    title: "Adaptive Snore Detection",
                    description: "Listens while you sleep and learns your snoring patterns. " +
                                 "All audio is processed on-device — nothing ever leaves your iPhone."
                )

                HowSnorryWorksFeatureRow(
                    icon: "applewatch",
                    iconColor: Theme.good,
                    title: "Snore alerts on your wrist",
                    description: "Connect your watch and get Snore alerts on your wrist. Snore alerts use standard iOS notifications, which may appear " +
                                 "on your paired watch as a gentle haptic nudge — small enough to " +
                                 "prompt a position change without fully waking you. There is no watchOS app."
                )

                HowSnorryWorksFeatureRow(
                    icon: "bell.slash.fill",
                    iconColor: Theme.warning,
                    title: "Alerts Stop Automatically",
                    description: "When snoring stops, alerts cease on their own after about 3 seconds of silence—no alarm to dismiss, no disruption beyond the nudge itself."
                )

                HowSnorryWorksFeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: Theme.snoring,
                    title: "Track Your Progress",
                    description: "Session history and Insights show your snore patterns over time " +
                                 "and how the alert feature is affecting them — see real improvement."
                )

                HowSnorryWorksFeatureRow(
                    icon: "square.and.arrow.up",
                    iconColor: Theme.accent,
                    title: "Share Snore Clips",
                    description: "Open any night in Sleep History and share individual event recordings " +
                                 "via AirDrop, Messages, or save—handy for a partner or clinician review."
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var overnightTipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.good)
                    .symbolRenderingMode(.hierarchical)
                Text("Overnight setup tips")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
            }

            VStack(alignment: .leading, spacing: 10) {
                overnightTipRow(
                    icon: "battery.100percent.bolt",
                    text: "Keep your iPhone plugged in. Snorry records audio all night—connect to a charger before you fall asleep to prevent battery drain."
                )
                overnightTipRow(
                    icon: "eye.slash.fill",
                    text: "Place your phone face down on your nightstand so the screen won't disturb your sleep."
                )
                overnightTipRow(
                    icon: "lock.fill",
                    text: "After you start a session, recording continues when you lock your phone or switch away from the app. Don't force-quit Snorry until you stop the session."
                )
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
                .strokeBorder(Theme.good.opacity(0.28), lineWidth: 1)
        )
    }

    private func overnightTipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.good)
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var earbudPartnerTipsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "earbuds")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .symbolRenderingMode(.hierarchical)
                Text("Private snore alerts for couples")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
            }

            Text(
                "If you share a bed, the in-app sound alarm can wake your partner when it plays " +
                "from the iPhone speaker. Wearing sleep earbuds lets only you hear the nudge."
            )
            .font(.caption)
            .foregroundStyle(Theme.labelSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                earbudTipRow(
                    icon: "moon.zzz.fill",
                    text: "Soundcore Sleep A30 sleep earbuds are very comfortable for overnight use—" +
                          "they stay comfortable when side-sleeping and are designed for wearing in bed."
                )
                earbudTipRow(
                    icon: "mic.fill",
                    text: "Snorry keeps listening through your iPhone’s built-in microphone for snore " +
                          "detection, even when earbuds are connected."
                )
                earbudTipRow(
                    icon: "speaker.wave.2.fill",
                    text: "When paired, the sound alarm plays through your earbuds instead of the " +
                          "phone speaker—so your partner is less likely to be disturbed."
                )
                earbudTipRow(
                    icon: "gearshape.fill",
                    text: "Turn on the sound alarm in Settings, connect your earbuds before you tap " +
                          "Start, and keep your iPhone on the nightstand within range."
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.accent.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Theme.radiusCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
        )
    }

    private func earbudTipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    "a clinician if you have concerns about sleep apnea or breathing."
                )
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
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

// MARK: - How Snorry works feature row

private struct HowSnorryWorksFeatureRow: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
