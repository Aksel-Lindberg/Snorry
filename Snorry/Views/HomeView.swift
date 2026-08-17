import SwiftUI
import AVFoundation
import SwiftData

// MARK: - Tonight home screen with big start button
struct HomeView: View {

    private enum ScrollTarget: String {
        case alertSetup
        case lastSession
        case scrollEnd
    }

    @Bindable var vm: MonitorViewModel
    @Binding var showRecordingScreen: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var alertSettingsRows: [AlertSettings]
    /// All sessions, newest first. Filter completed rows in-memory so `endDate` updates after stop
    /// are visible immediately (SwiftData `#Predicate` queries can lag when optional fields change).
    @Query(sort: \SnoreSession.startDate, order: .reverse)
    private var allSessions: [SnoreSession]

    /// Completed sessions only — stays valid when rows are deleted (avoids stale `SnoreSession` references).
    private var completedSessions: [SnoreSession] {
        allSessions.filter { $0.endDate != nil }
    }

    /// Most recent completed session worth showing on the Last Session card (skips empty accidental taps).
    private var lastDisplayableSession: SnoreSession? {
        completedSessions.first(where: \.hasLastSessionCardData)
    }
    @State private var showPermissions = false
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var scrollAlertIntoView = false
    @AppStorage(UserPreferences.displayNameKey) private var userDisplayName = ""
    @AppStorage(UserPreferences.hasSeenTonightWelcomeKey) private var hasSeenTonightWelcome = false
    @State private var isFirstTonightVisit = false

    /// START button diameter on iPad portrait (iPhone default is 172).
    private let padStartButtonDiameter: CGFloat = 118

    /// Side-by-side start + cards only in iPad landscape — portrait stacks vertically to avoid tab-bar overlap.
    private var usePadSideBySideLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    /// Tighter Monitor home on iPad portrait so Last Session stays above the tab bar.
    private var usesCompressedPadLayout: Bool {
        horizontalSizeClass == .regular && !usePadSideBySideLayout
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                mainContent(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationDestination(isPresented: $showRecordingScreen) {
                        MonitorView(vm: vm)
                    }
                    .sheet(isPresented: $showPermissions) {
                        PermissionsView(
                            vm: vm,
                            isPresented: $showPermissions,
                            showMonitor: $showRecordingScreen
                        )
                    }
            }
            .onAppear {
                ensureAlertSettingsRowExists()
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeAppIconMark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Help")
                        .accessibilityHint("Opens help and how-to for Snorry")

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Opens alert and app settings")
                    }
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpCenterView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(onDone: { showSettings = false })
            }
        }
    }

    private func mainContent(vm: MonitorViewModel) -> some View {
        Group {
            if horizontalSizeClass == .regular {
                padMonitorLayout(vm: vm)
            } else {
                compactMonitorLayout(vm: vm)
            }
        }
    }

    /// iPhone / compact — scrollable so cards clear the floating tab bar.
    private func compactMonitorLayout(vm: MonitorViewModel) -> some View {
        monitorScrollView(vm: vm) {
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 28)

                startButtonSection(vm: vm)
                    .padding(.top, 12)

                monitorBottomCards(vm: vm)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// iPad — portrait stacks vertically; landscape places start button beside cards.
    private func padMonitorLayout(vm: MonitorViewModel) -> some View {
        monitorScrollView(vm: vm) {
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, usesCompressedPadLayout ? 12 : 28)

                if usePadSideBySideLayout {
                    padLandscapeContent(vm: vm)
                } else {
                    padPortraitContent(vm: vm)
                }

                scrollEndSpacer
            }
            .padding(.bottom, usesCompressedPadLayout ? 16 : 24)
        }
    }

    private func monitorScrollView<Content: View>(
        vm: MonitorViewModel,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .scrollIndicators(.hidden)
            .clearsFloatingTabBar()
            .onChange(of: scrollAlertIntoView) { _, shouldScroll in
                guard shouldScroll else { return }
                scrollExpandedAlertCard(proxy: proxy)
                scrollAlertIntoView = false
            }
        }
    }

    /// Scrolls the expanded alert card into view above the tab bar.
    private func scrollExpandedAlertCard(proxy: ScrollViewProxy) {
        // Let the disclosure animation lay out before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(ScrollTarget.alertSetup, anchor: UnitPoint(x: 0.5, y: 0.06))
            }
        }
    }

    private var scrollEndSpacer: some View {
        Color.clear
            .frame(height: usesCompressedPadLayout ? 20 : 1)
            .id(ScrollTarget.scrollEnd)
    }

    private func padPortraitContent(vm: MonitorViewModel) -> some View {
        VStack(spacing: 0) {
            startButtonSection(vm: vm)
                .padding(.top, 8)

            monitorBottomCards(vm: vm)
                .padding(.horizontal, 40)
                .padding(.top, 10)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
    }

    private func padLandscapeContent(vm: MonitorViewModel) -> some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(spacing: 20) {
                startButtonSection(vm: vm)
            }
            .frame(minWidth: 260)

            monitorBottomCards(vm: vm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
    }

    /// Last session and alert setup (collapsed by default) — shared by phone and iPad layouts.
    private func monitorBottomCards(vm: MonitorViewModel) -> some View {
        let showCardShortcuts = !vm.isMonitoring

        return VStack(alignment: .leading, spacing: usesCompressedPadLayout ? 10 : 16) {
            recentSessionCard(showShortcut: showCardShortcuts)
                .id(ScrollTarget.lastSession)

            if let settings = alertSettingsRows.first {
                AlertSetupSummaryCard(
                    settings: settings,
                    notificationsAuthorized: vm.notificationAuthorized,
                    caption: "Used for the next recording session",
                    compact: true,
                    collapsible: true,
                    startsCollapsed: true,
                    onExpandedChange: { expanded in
                        if expanded {
                            scrollAlertIntoView = true
                        }
                    },
                    footerLinkTitle: showCardShortcuts ? "Change in Settings" : nil,
                    onFooterLinkTap: showCardShortcuts ? { showSettings = true } : nil
                )
                .id(ScrollTarget.alertSetup)
            }
        }
        .padding(.top, usesCompressedPadLayout ? 6 : 10)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            HandwrittenGradientText(
                text: UserPreferences.tonightHomeGreeting(
                    displayName: userDisplayName,
                    isFirstVisit: isFirstTonightVisit
                ),
                size: Theme.tonightGreetingFontSize(
                    compressedPad: usesCompressedPadLayout,
                    regularWidth: horizontalSizeClass == .regular
                )
            )

            Text("Sleep Snore Alert & Tracking")
                .font(Theme.handwritten(size: usesCompressedPadLayout ? 17 : 19))
                .foregroundStyle(Theme.handwrittenGradient)
                .padding(.top, usesCompressedPadLayout ? 3 : 5)
        }
        .onAppear {
            if !hasSeenTonightWelcome {
                isFirstTonightVisit = true
            }
        }
        .onDisappear {
            if isFirstTonightVisit {
                hasSeenTonightWelcome = true
                isFirstTonightVisit = false
            }
        }
    }

    private func startButtonSection(vm: MonitorViewModel) -> some View {
        let buttonSize: CGFloat = {
            if usesCompressedPadLayout { return padStartButtonDiameter }
            if horizontalSizeClass == .regular { return 160 }
            return 172
        }()
        let captionSpacing: CGFloat = usesCompressedPadLayout ? 6 : 8
        let sessionActiveOnHome = vm.isMonitoring && !showRecordingScreen

        return VStack(spacing: captionSpacing) {
            Button {
                handleStartTap(vm: vm)
            } label: {
                SleepAnimationView(presentation: .startButton, diameter: buttonSize)
            }
            .disabled(vm.microphonePermission == .denied)
            .buttonStyle(.plain)
            .opacity(vm.microphonePermission == .denied ? 0.42 : 1)
            .accessibilityLabel(sessionActiveOnHome ? "Return to recording" : "Start recording")
            .accessibilityHint(
                sessionActiveOnHome
                    ? "Opens the active recording session"
                    : "Begins an overnight snore recording session"
            )

            if sessionActiveOnHome {
                Text("Return to recording")
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelSecondary)
                    .multilineTextAlignment(.center)
            } else if isFirstTonightVisit {
                Text("Tap to start recording")
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            if vm.microphonePermission == .undetermined ||
               vm.microphonePermission == .denied {
                permissionPrompt(vm: vm)
            }

        }
    }

    /// Ensures the singleton settings row exists so the home card can read alerts configuration.
    private func ensureAlertSettingsRowExists() {
        guard alertSettingsRows.isEmpty else { return }
        _ = AlertSettings.load(context: context)
    }

    private func permissionPrompt(vm: MonitorViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(Theme.snoring)
            Text(vm.microphonePermission == .denied
                 ? "Microphone access denied — enable in Settings"
                 : "Microphone access required to record snoring")
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recentSessionCard(showShortcut: Bool) -> some View {
        let cardPadding: CGFloat = usesCompressedPadLayout ? 12 : (horizontalSizeClass == .regular ? 14 : 12)
        let lastSession = lastDisplayableSession

        VStack(alignment: .leading, spacing: usesCompressedPadLayout ? 6 : (horizontalSizeClass == .regular ? 8 : 6)) {
            Label("Last Session", systemImage: "clock")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelPrimary)

            if let session = lastSession {
                lastSessionMetrics(session: session)

                if showShortcut {
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        CardFooterTextLink(title: "View details")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            } else {
                lastSessionEmptyMetrics
                Text("No recordings yet.")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(cardPadding)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var lastSessionEmptyMetrics: some View {
        HStack(alignment: .top, spacing: 0) {
            summaryItem(label: "Sleep duration", value: "—")
            summaryItem(label: "Snore events", value: "—")
            summaryItem(label: "Snore duration", value: "—")
        }
    }

    private func lastSessionMetrics(session: SnoreSession) -> some View {
        HStack(alignment: .top, spacing: 0) {
            summaryItem(label: "Sleep duration", value: session.displayDurationSummary)
            summaryItem(label: "Snore events", value: "\(session.displayEventCount)")
            summaryItem(label: "Snore duration", value: session.displayTotalSnoreTime)
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        let valueSize: CGFloat = usesCompressedPadLayout ? 16 : (horizontalSizeClass == .regular ? 17 : 15)
        return VStack(spacing: 1) {
            Text(value)
                .font(Theme.monoDigit(size: valueSize))
                .foregroundStyle(Theme.labelPrimary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func handleStartTap(vm: MonitorViewModel) {
        switch vm.microphonePermission {
        case .granted:
            beginMonitoringIfAllowed(vm: vm)
        case .undetermined:
            showPermissions = true
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func beginMonitoringIfAllowed(vm: MonitorViewModel) {
        if vm.isMonitoring {
            showRecordingScreen = true
            return
        }

        vm.startMonitoring()
        showRecordingScreen = true
    }
}
