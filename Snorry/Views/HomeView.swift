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

            SleepAnimationView()
                .padding(.top, 12)

            Spacer(minLength: 16)

            startButtonSection(vm: vm)

            if let settings = alertSettingsRows.first {
                sessionSetupCard(settings: settings, vm: vm)
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
            // Fixed layout — no pulsing or looping animations so the button stays predictable.
            Button {
                handleStartTap(vm: vm)
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 160, height: 160)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.28), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

                    VStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .semibold))
                        Text("START")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .tracking(3)
                    }
                    .foregroundStyle(.white)
                }
            }
            .disabled(vm.microphonePermission == .denied)
            .buttonStyle(.plain)

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

    // MARK: Session alert summary (matches Settings until you tap Start)

    private func sessionSetupCard(settings: AlertSettings, vm: MonitorViewModel) -> some View {
        let style = AlarmStyle(rawValue: settings.alarmStyleRaw) ?? .classic

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Alert setup", systemImage: "bell.and.waves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)
                Text("Used for the next monitoring session")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                sessionInfoRow(
                    icon: "bell.badge.fill",
                    iconTint: settings.pushNotificationEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Push notifications",
                    detail: pushNotificationSummary(settings: settings)
                )

                sessionInfoRow(
                    icon: "speaker.wave.3.fill",
                    iconTint: settings.soundAlarmEnabled ? Theme.accent : Theme.labelTertiary,
                    title: "Sound alarm",
                    detail: soundAlarmSummary(settings: settings)
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
                    Text(alarmSoundFootnote(for: style))
                        .font(.caption2)
                        .foregroundStyle(Theme.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .opacity(settings.soundAlarmEnabled ? 1 : 0.45)

            if settings.pushNotificationEnabled && !vm.notificationAuthorized {
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

    private func sessionInfoRow(icon: String, iconTint: Color, title: String, detail: String) -> some View {
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

    private func pushNotificationSummary(settings: AlertSettings) -> String {
        guard settings.pushNotificationEnabled else {
            return "Off"
        }
        let repeatEvery = Int(settings.pushRepeatIntervalSeconds)
        return "On · first push after 2 s of snoring · repeats every \(repeatEvery) s"
    }

    private func soundAlarmSummary(settings: AlertSettings) -> String {
        guard settings.soundAlarmEnabled else {
            return "Off"
        }
        let delay = Int(settings.soundAlarmAfterSeconds)
        let pct = Int((settings.alarmVolume * 100).rounded())
        return "On · starts after \(delay) s · volume \(pct)%"
    }

    /// Bundled clips show the `.mp3` name; synthesized styles show their subtitle line.
    private func alarmSoundFootnote(for style: AlarmStyle) -> String {
        if let clip = style.bundledClipName {
            return "\(clip).mp3"
        }
        return style.subtitle
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
