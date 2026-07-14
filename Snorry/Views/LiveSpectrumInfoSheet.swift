import SwiftUI

// MARK: - Technical detail for Live Power Spectrum (opened from info button on Recording screen)
struct LiveSpectrumInfoSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        spectrumSection
                        metricsSection
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Live Power Spectrum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    private var spectrumSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you’re seeing")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            Text(
                "Log-scaled band energy from 45 Hz up to the Nyquist frequency. " +
                "Bars brighten when snoring is confirmed so you can see how the sound shifts in real time."
            )
            .font(.subheadline)
            .foregroundStyle(Theme.labelSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live metrics")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)

            infoRow(
                icon: "speaker.wave.2.fill",
                title: "dBFS",
                detail: "Input loudness (— when extremely quiet)."
            )
            infoRow(
                icon: "waveform.badge.exclamationmark",
                title: "Events",
                detail: "Completed snore bouts—not every classifier frame."
            )
        }
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
