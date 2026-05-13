import SwiftUI
import AVFoundation
import SwiftData

// MARK: - Home screen with big start button
struct HomeView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var alertSettingsRows: [AlertSettings]
    /// Completed sessions only — stays valid when rows are deleted (avoids stale `SnoreSession` references).
    @Query(
        filter: #Predicate<SnoreSession> { $0.endDate != nil },
        sort: \SnoreSession.startDate,
        order: .reverse
    )
    private var completedSessions: [SnoreSession]
    @State private var vm: MonitorViewModel?
    @State private var showMonitor = false
    @State private var showPermissions = false
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                if let vm {
                    mainContent(vm: vm)
                        .navigationDestination(isPresented: $showMonitor) {
                            MonitorView(vm: vm)
                        }
                        .sheet(isPresented: $showPermissions) {
                            PermissionsView(vm: vm, isPresented: $showPermissions)
                        }
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
            .onAppear {
                setupViewModel()
                ensureAlertSettingsRowExists()
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("HomeAppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel("Snorry")
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpCenterView()
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

    /// iPhone / compact split — original vertical stack.
    private func compactMonitorLayout(vm: MonitorViewModel) -> some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 28)

            startButtonSection(vm: vm)
                .padding(.top, 12)

            if let settings = alertSettingsRows.first {
                AlertSetupSummaryCard(
                    settings: settings,
                    notificationsAuthorized: vm.notificationAuthorized,
                    caption: "Used for the next monitoring session",
                    compact: true
                )
                .padding(.top, 10)
            }

            Spacer(minLength: 6)

            recentSessionCard()
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    /// iPad / regular width — uses horizontal space without stretching a single narrow column.
    private func padMonitorLayout(vm: MonitorViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 28)

                HStack(alignment: .top, spacing: 40) {
                    VStack(spacing: 20) {
                        startButtonSection(vm: vm)
                    }
                    .frame(minWidth: 260)

                    VStack(alignment: .leading, spacing: 16) {
                        if let settings = alertSettingsRows.first {
                            AlertSetupSummaryCard(
                                settings: settings,
                                notificationsAuthorized: vm.notificationAuthorized,
                                caption: "Used for the next monitoring session",
                                compact: true
                            )
                        }
                        recentSessionCard()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 44)
                .padding(.top, 28)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)

                Color.clear.frame(height: 28)
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            // App wordmark
            Text("Snorry")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.labelPrimary)

            // Handwritten tagline with gradient shimmer
            Text("Sleep Snore Alert & Tracking")
                .font(Theme.handwritten(size: 19))
                .foregroundStyle(Theme.handwrittenGradient)
                .padding(.top, 5)

            // Watch hint — lighter handwritten italic
            Text("Connect your watch · get Snore alerts on your wrist")
                .font(Theme.handwritten(size: 13, bold: false))
                .italic()
                .foregroundStyle(Color.white.opacity(0.52))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    private func startButtonSection(vm: MonitorViewModel) -> some View {
        VStack(spacing: 14) {
            Button {
                handleStartTap(vm: vm)
            } label: {
                SleepAnimationView(presentation: .startButton)
                    .accessibilityLabel("Start monitoring")
                    .accessibilityHint("Begins snore detection using the microphone")
            }
            .disabled(vm.microphonePermission == .denied)
            .buttonStyle(.plain)
            .opacity(vm.microphonePermission == .denied ? 0.42 : 1)

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
                 : "Microphone access required to monitor snoring")
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recentSessionCard() -> some View {
        if let session = completedSessions.first {
            let cardPadding: CGFloat = horizontalSizeClass == .regular ? 14 : 12
            VStack(alignment: .leading, spacing: horizontalSizeClass == .regular ? 8 : 6) {
                Label("Last Session", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)

                if horizontalSizeClass == .regular {
                    lastSessionMetrics(session: session)
                } else {
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            summaryItem(label: "Sleep duration", value: session.displayDurationSummary)
                            summaryItem(label: "Events", value: "\(session.displayEventCount)")
                            summaryItem(label: "Snoring", value: session.displaySnoringPercent)
                        }
                        HStack(spacing: 0) {
                            summaryItem(label: "Total snore", value: session.displayTotalSnoreTime)
                            summaryItem(label: "Avg / event", value: session.displayAvgSnoreTimePerEvent)
                        }
                    }
                }
            }
            .padding(cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        }
    }

    /// Single-row metric strip for iPad / wide Monitor layout.
    private func lastSessionMetrics(session: SnoreSession) -> some View {
        HStack(spacing: 0) {
            summaryItem(label: "Sleep duration", value: session.displayDurationSummary)
            summaryItem(label: "Events", value: "\(session.displayEventCount)")
            summaryItem(label: "Total snore", value: session.displayTotalSnoreTime)
            summaryItem(label: "Avg / event", value: session.displayAvgSnoreTimePerEvent)
            summaryItem(label: "Snoring", value: session.displaySnoringPercent)
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        let valueSize: CGFloat = horizontalSizeClass == .regular ? 17 : 15
        return VStack(spacing: 1) {
            Text(value)
                .font(Theme.monoDigit(size: valueSize))
                .foregroundStyle(Theme.labelPrimary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.labelTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func setupViewModel() {
        guard vm == nil else { return }
        let newVM = MonitorViewModel(modelContext: context)
        vm = newVM
        Task { await newVM.syncNotificationAuthorizationFromSystem() }
    }

    private func handleStartTap(vm: MonitorViewModel) {
        switch vm.microphonePermission {
        case .granted:
            vm.startMonitoring()
            showMonitor = true
        case .undetermined:
            showPermissions = true
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
}
