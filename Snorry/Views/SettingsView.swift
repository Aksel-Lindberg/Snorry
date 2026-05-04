import SwiftUI
import SwiftData

// MARK: - Alert threshold configuration
struct SettingsView: View {

    @Environment(\.modelContext) private var context
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
            .onAppear {
                if vm == nil { vm = SettingsViewModel(context: context) }
            }
        }
    }

    private func settingsContent(vm: SettingsViewModel) -> some View {
        List {
            detectionSection(vm: vm)
            alertTimingsSection(vm: vm)
            volumeSection(vm: vm)
            actionsSection(vm: vm)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func detectionSection(vm: SettingsViewModel) -> some View {
        Section {
            SensitivityRow(
                value: Binding(
                    get: { vm.snoringDetectionSensitivity },
                    set: { vm.snoringDetectionSensitivity = $0; vm.save() }
                )
            )
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

    private func alertTimingsSection(vm: SettingsViewModel) -> some View {
        Section {
            SliderRow(
                label: "Notify after",
                value: Binding(
                    get: { vm.notifyDelay },
                    set: { vm.notifyDelay = $0; vm.save() }
                ),
                range: 2...120,
                unit: "s",
                step: 1
            )
            SliderRow(
                label: "Low alarm after",
                value: Binding(
                    get: { vm.audioLowDelay },
                    set: { vm.audioLowDelay = $0; vm.save() }
                ),
                range: 5...180,
                unit: "s",
                step: 1
            )
            SliderRow(
                label: "Medium alarm after",
                value: Binding(
                    get: { vm.audioMedDelay },
                    set: { vm.audioMedDelay = $0; vm.save() }
                ),
                range: 10...240,
                unit: "s",
                step: 1
            )
            SliderRow(
                label: "Full alarm after",
                value: Binding(
                    get: { vm.audioHighDelay },
                    set: { vm.audioHighDelay = $0; vm.save() }
                ),
                range: 15...300,
                unit: "s",
                step: 1
            )
            SliderRow(
                label: "Clear after silence",
                value: Binding(
                    get: { vm.clearDelay },
                    set: { vm.clearDelay = $0; vm.save() }
                ),
                range: 2...20,
                unit: "s",
                step: 1
            )
        } header: {
            Text("Alert Timings")
                .foregroundStyle(Theme.labelSecondary)
        }
        .listRowBackground(Theme.surface)
    }

    private func volumeSection(vm: SettingsViewModel) -> some View {
        Section {
            VolumeRow(label: "Low volume",
                      value: Binding(get: { Double(vm.volumeLow) },
                                     set: { vm.volumeLow = Float($0); vm.save() }))
            VolumeRow(label: "Medium volume",
                      value: Binding(get: { Double(vm.volumeMed) },
                                     set: { vm.volumeMed = Float($0); vm.save() }))
            VolumeRow(label: "Full volume",
                      value: Binding(get: { Double(vm.volumeHigh) },
                                     set: { vm.volumeHigh = Float($0); vm.save() }))
        } header: {
            Text("Alarm Volumes")
                .foregroundStyle(Theme.labelSecondary)
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

    /// Maps the 1–5 integer level to a human-readable label.
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
            Slider(value: $value, in: 0.05...1.0, step: 0.05)
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }
}
