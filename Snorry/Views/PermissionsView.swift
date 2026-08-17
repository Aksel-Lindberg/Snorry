import SwiftUI
import AVFoundation

// MARK: - Onboarding permissions sheet
struct PermissionsView: View {

    let vm: MonitorViewModel
    @Binding var isPresented: Bool
    @Binding var showMonitor: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(Theme.accent)

                    VStack(spacing: 8) {
                        Text("Microphone Access")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.labelPrimary)
                        Text("Snorry uses your microphone to detect snoring. Audio is processed entirely on-device and only short clips are saved.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.labelSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    VStack(spacing: 14) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "Microphone",
                            description: "Required to detect snoring sounds.",
                            granted: vm.microphonePermission == .granted
                        )
                        PermissionRow(
                            icon: "bell.badge.fill",
                            title: "Notifications",
                            description: "Optional — receive alerts when snoring is detected.",
                            granted: vm.notificationAuthorized
                        )
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await vm.requestMicrophonePermission()
                                if vm.microphonePermission == .granted {
                                    beginMonitoringIfAllowed()
                                }
                            }
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.accentGradient,
                                            in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                        }

                        Button {
                            isPresented = false
                        } label: {
                            Text("Not Now")
                                .font(.subheadline)
                                .foregroundStyle(Theme.labelSecondary)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .task {
                await vm.syncNotificationAuthorizationFromSystem()
            }
        }
    }

    private func beginMonitoringIfAllowed() {
        isPresented = false
        vm.startMonitoring()
        showMonitor = true
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
            }

            Spacer()

            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Theme.good : Theme.labelTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}
