import SwiftUI
import SwiftData

// MARK: - Alert threshold configuration
struct SettingsView: View {

    /// When embedded in a tab, `dismiss()` does nothing — call this to return to the Monitor tab.
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @State private var vm: SettingsViewModel?

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
        }
    }

    // MARK: Content

    private func settingsContent(vm: SettingsViewModel) -> some View {
        List {
            detectionSection(vm: vm)
            alarmStyleSection(vm: vm)
            alertTimingsSection(vm: vm)
            volumeSection(vm: vm)
            actionsSection(vm: vm)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: Sections

    private func detectionSection(vm: SettingsViewModel) -> some View {
        Section {
            SensitivityRow(value: Binding(
                get: { vm.snoringDetectionSensitivity },
                set: { vm.snoringDetectionSensitivity = $0 }
            ))
        } header: {
            Text("Snore Detection")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text("Higher sensitivity catches quieter snores but may increase false positives.")
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func alarmStyleSection(vm: SettingsViewModel) -> some View {
        Section {
            ForEach(AlarmStyle.allCases, id: \.rawValue) { style in
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
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Alarm Style")
                .foregroundStyle(Theme.labelSecondary)
        }
        .listRowBackground(Theme.surface)
    }

    private func alertTimingsSection(vm: SettingsViewModel) -> some View {
        Section {
            SliderRow(
                label: "Send push notification after",
                value: Binding(get: { vm.notifyDelay },
                               set: { vm.notifyDelay = $0 }),
                range: 2...120,
                unit: "s",
                step: 1
            )
            SliderRow(
                label: "Sound alarm after",
                value: Binding(get: { vm.soundAlarmAfter },
                               set: { vm.soundAlarmAfter = $0 }),
                range: 5...300,
                unit: "s",
                step: 1
            )
            SliderRow(
                label: "Silence to end snore event",
                value: Binding(get: { vm.clearDelay },
                               set: { vm.clearDelay = $0 }),
                range: 3...30,
                unit: "s",
                step: 1
            )
        } header: {
            Text("Alert Timings")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text("Sound alarm after: continuous snoring time before the alarm starts (then volume rises every 2 s). Silence to end snore event: no snoring for this long ends the bout.")
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func volumeSection(vm: SettingsViewModel) -> some View {
        Section {
            VolumeRow(label: "Volume",
                      value: Binding(get: { Double(vm.alarmVolume) },
                                     set: { vm.alarmVolume = Float($0) }))
        } header: {
            Text("Alarm")
                .foregroundStyle(Theme.labelSecondary)
        } footer: {
            Text("Maximum loudness for the alarm. Playback starts low and steps up every 2 seconds toward this level.")
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption)
        }
        .listRowBackground(Theme.surface)
    }

    private func actionsSection(vm: SettingsViewModel) -> some View {
        Section {
            Button("Reset to Defaults") {
                vm.reset()
            }
            .foregroundStyle(Theme.snoring)
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

private struct SensitivityRow: View {
    @Binding var value: Double

    private var label: String {
        switch Int(value) {
        case 1: return "Very Low"
        case 2: return "Low"
        case 3: return "Medium"
        case 4: return "High"
        case 5: return "Very High"
        default: return "Medium"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sensitivity")
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text(label)
                    .font(Theme.monoDigit(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            Slider(value: $value, in: 1...5, step: 1)
                .tint(Theme.accent)
            HStack {
                Text("Low")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelSecondary)
                Spacer()
                Text("High")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelSecondary)
            }
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
