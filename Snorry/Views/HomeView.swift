import SwiftUI
import AVFoundation
import SwiftData

// MARK: - Home screen with big start button
struct HomeView: View {

    @Environment(\.modelContext) private var context
    @State private var vm: MonitorViewModel?
    @State private var showMonitor = false
    @State private var showPermissions = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3

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
            .onAppear { setupViewModel() }
        }
    }

    private func mainContent(vm: MonitorViewModel) -> some View {
        VStack(spacing: 0) {
            headerSection
            Spacer()
            startButtonSection(vm: vm)
            Spacer()
            recentSessionCard(vm: vm)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
    }

    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "zzz")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(Theme.accent)
                .padding(.top, 40)

            Text("Snorry")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.labelPrimary)

            Text("Sleep Snore Tracker")
                .font(.subheadline)
                .foregroundStyle(Theme.labelSecondary)
        }
    }

    private func startButtonSection(vm: MonitorViewModel) -> some View {
        VStack(spacing: 24) {
            ZStack {
                // Outer glow rings
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Theme.accent.opacity(glowOpacity / Double(i + 1)), lineWidth: 1.5)
                        .frame(width: 180 + CGFloat(i) * 30,
                               height: 180 + CGFloat(i) * 30)
                        .scaleEffect(pulseScale)
                }

                // Main button
                Button {
                    handleStartTap(vm: vm)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.accentGradient)
                            .frame(width: 160, height: 160)
                            .shadow(color: Theme.accentGlow, radius: 30)

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
            }
            .animation(
                .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                value: pulseScale
            )
            .onAppear { pulseScale = 1.05; glowOpacity = 0.5 }

            if vm.microphonePermission == .undetermined ||
               vm.microphonePermission == .denied {
                permissionPrompt(vm: vm)
            }
        }
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
