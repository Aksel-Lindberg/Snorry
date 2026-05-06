import SwiftUI
import AVFoundation
import SwiftData

// MARK: - Home screen with big start button
struct HomeView: View {

    @Environment(\.modelContext) private var context
    @Query private var alertSettingsRows: [AlertSettings]
    @State private var vm: MonitorViewModel?
    @State private var showMonitor = false
    @State private var showPermissions = false

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
        }
    }

    private func mainContent(vm: MonitorViewModel) -> some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 36)

            startButtonSection(vm: vm)
                .padding(.top, 20)

            if let settings = alertSettingsRows.first {
                AlertSetupSummaryCard(
                    settings: settings,
                    notificationsAuthorized: vm.notificationAuthorized,
                    caption: "Used for the next monitoring session"
                )
                .padding(.top, 20)
            }

            Spacer(minLength: 16)

            recentSessionCard(vm: vm)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
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
                .foregroundStyle(Theme.labelTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    private func startButtonSection(vm: MonitorViewModel) -> some View {
        VStack(spacing: 24) {
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
    private func recentSessionCard(vm: MonitorViewModel) -> some View {
        if let session = vm.recentSession {
            VStack(alignment: .leading, spacing: 10) {
                Label("Last Session", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)

                HStack(spacing: 0) {
                    summaryItem(label: "Duration",
                                value: SessionDetailViewModel(session: session).durationString)
                    summaryItem(label: "Events",
                                value: "\(session.eventCount)")
                    summaryItem(label: "BRPM avg",
                                value: session.avgBRPM > 0
                                       ? String(format: "%.0f", session.avgBRPM) : "—")
                    summaryItem(label: "Snoring",
                                value: SessionDetailViewModel(session: session).snorePercentString)
                }
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        }
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.monoDigit(size: 18))
                .foregroundStyle(Theme.labelPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.labelTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func setupViewModel() {
        guard vm == nil else { return }
        let newVM = MonitorViewModel(modelContext: context)
        vm = newVM
        Task { await newVM.requestNotifications() }
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
