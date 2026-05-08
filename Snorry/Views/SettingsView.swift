import SwiftUI
import SwiftData

// MARK: - Alert threshold configuration
struct SettingsView: View {

    /// When embedded in a tab, `dismiss()` does nothing — call this to return to the Monitor tab.
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var vm: SettingsViewModel?
    @State private var confirmDeleteAllLogs = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                if let vm {
                    settingsContent(vm: vm)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        vm?.cancel()
                        dismiss()
                        onDone?()
                    }
                    .foregroundStyle(Theme.labelSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        vm?.save()
                        dismiss()
                        onDone?()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
            .onAppear {
                if vm == nil { vm = SettingsViewModel(context: context) }
            }
            .onDisappear {
                vm?.stopAlarmStylePreview()
            }
        }
    }

    // MARK: Content

    private func settingsContent(vm: SettingsViewModel) -> some View {
        List {
            alertChannelsSection(vm: vm)
            alertTimingsSection(vm: vm)
            volumeSection(vm: vm)
            alarmStyleSection(vm: vm)
            actionsSection(vm: vm)
            legalSection()
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .frame(maxWidth: horizontalSizeClass == .regular ? 820 : .infinity)
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "Delete all sleep logs and settings history?",
            isPresented: $confirmDeleteAllLogs,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                vm.deleteAllSleepAndSettingsLogs()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes every saved sleep session, snore clips, and settings-change markers used in analytics. Your current Settings values are not changed."
            )
        }
        .alert(
            "Couldn’t Delete Logs",
            isPresented: Binding(
                get: { vm.deleteLogsFailedMessage != nil },
                set: { if !$0 { vm.clearDeleteLogsError() } }
            )
        ) {
            Button("OK", role: .cancel) { vm.clearDeleteLogsError() }
        } message: {
            Text(vm.deleteLogsFailedMessage ?? "")
        }
    }

    // MARK: Sections

    private func alertChannelsSection(vm: SettingsViewModel) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { vm.pushNotificationEnabled },
                set: { vm.pushNotificationEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push notifications")
                        .font(.subheadline)
                    Text("Local alerts on this iPhone")
                        .font(.caption)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .tint(Theme.accent)

            Toggle(isOn: Binding(
                get: { vm.soundAlarmEnabled },
                set: {
                    vm.soundAlarmEnabled = $0
                    if !$0 { vm.stopAlarmStylePreview() }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound alarm")
                        .font(.subheadline)
                    Text("In-app alarm tone while monitoring")
                        .font(.caption)
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .tint(Theme.accent)

            SliderRow(
                label: "Repeat Push notification every",
                value: Binding(get: { vm.pushRepeatInterval },
                               set: { vm.pushRepeatInterval = $0 }),
                range: 1...10,
                unit: "s",
                step: 1
            )
            .disabled(!vm.pushNotificationEnabled)
            .opacity(vm.pushNotificationEnabled ? 1 : 0.45)
        } header: {
            Text("Alert channels")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Turn on one or both. With both on: push fires first, then sound after the configured delay. Sound-only skips push; push-only never plays sound.")
                    .foregroundStyle(Theme.labelSecondary)
                if !vm.pushNotificationEnabled && !vm.soundAlarmEnabled {
                    Text("No alerts will fire until you enable push and/or sound.")
                        .foregroundStyle(Theme.snoring)
                }
            }
            .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func alarmStyleSection(vm: SettingsViewModel) -> some View {
        Section {
            ForEach(AlarmStyle.allCases, id: \.rawValue) { style in
                HStack(spacing: 12) {
                    Button {
                        vm.alarmStyle = style
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: vm.alarmStyle == style
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundStyle(vm.alarmStyle == style
                                                 ? Theme.accent : Theme.labelTertiary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.labelPrimary)
                                Text(style.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.labelSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(vm.isPreviewing(style: style) ? "Stop" : "Play") {
                        vm.toggleAlarmStylePreview(for: style)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(vm.isPreviewing(style: style)
                                  ? Theme.snoring.opacity(0.18)
                                  : Theme.accent.opacity(0.18))
                    )
                    .foregroundStyle(vm.isPreviewing(style: style) ? Theme.snoring : Theme.accent)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Alarm Style")
                .foregroundStyle(Theme.labelSecondary)
        }
        .opacity(vm.soundAlarmEnabled ? 1 : 0.45)
        .disabled(!vm.soundAlarmEnabled)
        .listRowBackground(Theme.surface)
    }

    private func alertTimingsSection(vm: SettingsViewModel) -> some View {
        Section {
            TimingInfoRow(label: "Send push notification after", value: "2 s")
                .opacity(vm.pushNotificationEnabled ? 1 : 0.45)
            SliderRow(
                label: "Sound alarm after",
                value: Binding(get: { vm.soundAlarmAfter },
                               set: { vm.soundAlarmAfter = $0 }),
                range: 1...30,
                unit: "s",
                step: 1
            )
            .disabled(!vm.soundAlarmEnabled)
            .opacity(vm.soundAlarmEnabled ? 1 : 0.45)
        } header: {
            Text("Alert Timings")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text(
                "Push notification fires after a fixed 2 s. Sound alarm fires after the selected delay " +
                "(from snoring start). Alerts stay active until snoring has stopped for 3 s."
            )
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func volumeSection(vm: SettingsViewModel) -> some View {
        Section {
            VolumeRow(label: "Master volume",
                      value: Binding(get: { Double(vm.alarmVolume) },
                                     set: { vm.alarmVolume = Float($0) }))
        } header: {
            Text("Sound Alert")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text("Controls alert playback volume and style preview volume.")
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .opacity(vm.soundAlarmEnabled ? 1 : 0.45)
        .disabled(!vm.soundAlarmEnabled)
        .listRowBackground(Theme.surface)
    }

    private func actionsSection(vm: SettingsViewModel) -> some View {
        Section {
            Button("Reset to Defaults") {
                vm.reset()
            }
            .foregroundStyle(Theme.snoring)

            Button("Delete All Sleep & Settings Logs", role: .destructive) {
                confirmDeleteAllLogs = true
            }
        } footer: {
            Text(
                "Delete All removes every sleep session, waveform, snore clip, and settings-change history. Current preferences stay as they are."
            )
            .foregroundStyle(Theme.labelSecondary)
            .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func legalSection() -> some View {
        Section {
            Link("Terms of Use (EULA)", destination: LegalLinks.termsOfUse)
                .foregroundStyle(Theme.accent)
            Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
                .foregroundStyle(Theme.accent)
        } header: {
            Text("Legal")
                .foregroundStyle(Theme.labelSecondary)
        }
        .listRowBackground(Theme.surface)
    }
}

// MARK: - Reusable slider rows

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(Theme.monoDigit(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

/// Read-only row that displays a fixed timing value alongside its label.
private struct TimingInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.labelPrimary)
            Spacer()
            Text(value)
                .font(Theme.monoDigit(size: 13))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

private struct VolumeRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(Theme.monoDigit(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            Slider(value: $value, in: 0.10...1.0, step: 0.05)
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}
