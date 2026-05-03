import SwiftUI
import Charts

// MARK: - Live monitoring screen
struct MonitorView: View {

    @Bindable var vm: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    statusBadge
                    spectrumCard
                    metricsRow
                    alertPhaseCard
                    timelineCard
                    stopButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Monitoring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Dismiss whenever monitoring stops (button tap or external cause)
        .onChange(of: vm.isMonitoring) { _, monitoring in
            if !monitoring { dismiss() }
        }
    }

    // MARK: Sub-views

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(badgeColor)
                .frame(width: 10, height: 10)
                .scaleEffect(pulseAnimation && vm.detectionPhase == .confirmed ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                           value: pulseAnimation)

            Text(badgeLabel)
                .font(.headline)
                .foregroundStyle(badgeColor)

            Spacer()

            Text(elapsedString)
                .font(Theme.monoDigit(size: 14))
                .foregroundStyle(Theme.labelSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .onAppear { pulseAnimation = true }
    }

    private var badgeLabel: String {
        switch vm.detectionPhase {
        case .quiet:     return "Quiet"
        case .detecting: return "Detecting Pattern…"
        case .confirmed: return "Snoring Detected"
        }
    }

    private var badgeColor: Color {
        switch vm.detectionPhase {
        case .quiet:     return Theme.good
        case .detecting: return Theme.warning
        case .confirmed: return Theme.snoring
        }
    }

    private var spectrumCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Power Spectrum")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelSecondary)

            Text("Log‑scaled power spectrum (45 Hz … Nyquist); red bars/rings = BRPM harmonic of breath tempo.")
                .font(.caption2)
                .foregroundStyle(Theme.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)

            LivePowerSpectrumView(
                bands: vm.spectrumBands,
                isSnoring: vm.isSnoring,
                brpmHighlightBandIndex: vm.spectrumBRPMHighlightBandIndex,
                brpmHarmonicFrequencyHz: vm.spectrumBRPMHighlightHz,
                emphasiseMarker: vm.isSnoring && vm.isEpisodeConfirmed
            )
            .frame(height: 104)

            HStack(alignment: .firstTextBaseline) {
                Text("45 Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.labelTertiary)
                Spacer()
                if let hz = vm.spectrumBRPMHighlightHz, vm.isEpisodeConfirmed, vm.brpmAvailable {
                    Text(String(format: "~%.0f Hz harmonic", hz))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.red.opacity(vm.isSnoring ? 1 : 0.65))
                }
                Spacer()
                Text("\(nyquistLabel) Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.labelTertiary)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var nyquistLabel: String {
        let n = Int(AudioMonitorService.targetSampleRate / 2)
        if n >= 1000 { return String(format: "%.0fk", Double(n) / 1000) }
        return "\(n)"
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            MetricTile(
                label: "dBFS",
                value: vm.currentDB > -160 ? String(format: "%.0f", vm.currentDB) : "—",
                icon: "speaker.wave.3",
                color: Theme.accent
            )
            MetricTile(
                label: "BRPM",
                value: vm.brpmAvailable ? String(format: "%.0f", vm.currentBRPM) : "—",
                icon: "lungs",
                color: Theme.snoring
            )
            MetricTile(
                label: "Events",
                value: "\(vm.snoreEventCount)",
                icon: "waveform.badge.exclamationmark",
                color: Theme.good
            )
        }
    }

    private var alertPhaseCard: some View {
        Group {
            if vm.alertPhase != .idle {
                HStack(spacing: 10) {
                    Image(systemName: alertIcon)
                        .font(.title3)
                        .foregroundStyle(alertColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alertTitle)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.labelPrimary)
                        Text(alertSubtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.labelSecondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(alertColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusCard)
                        .stroke(alertColor.opacity(0.35), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: vm.alertPhase)
    }

    @ViewBuilder
    private var timelineCard: some View {
        if !vm.timelinePoints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Timeline")
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)

                LiveTimelineChart(points: vm.timelinePoints)
                    .frame(height: 132)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        }
    }

    private var stopButton: some View {
        Button {
            vm.stopMonitoring()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                Text("Stop Monitoring")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.snoringGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        }
    }

    // MARK: Helpers

    private var elapsedString: String {
        let h = vm.elapsedSeconds / 3600
        let m = vm.elapsedSeconds % 3600 / 60
        let s = vm.elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private var alertIcon: String {
        switch vm.alertPhase {
        case .notified:  return "bell.badge"
        case .audioLow:  return "speaker.wave.1"
        case .audioMedium: return "speaker.wave.2"
        case .audioHigh: return "speaker.wave.3.fill"
        default:         return "bell"
        }
    }

    private var alertTitle: String {
        switch vm.alertPhase {
        case .notified:   return "Notification Sent"
        case .audioLow:   return "Alarm: Low"
        case .audioMedium: return "Alarm: Medium"
        case .audioHigh:  return "Alarm: Loud"
        case .cleared:    return "Alert Cleared"
        default:          return ""
        }
    }

    private var alertSubtitle: String {
        switch vm.alertPhase {
        case .notified:   return "Check your phone to acknowledge."
        case .audioLow:   return "Increasing in 30 s if snoring continues."
        case .audioMedium: return "Increasing in 30 s if snoring continues."
        case .audioHigh:  return "Maximum volume. Wake up!"
        case .cleared:    return "Snoring stopped."
        default:          return ""
        }
    }

    private var alertColor: Color {
        switch vm.alertPhase {
        case .notified:   return .yellow
        case .audioLow:   return .orange
        case .audioMedium: return .orange
        case .audioHigh:  return Theme.snoring
        case .cleared:    return Theme.good
        default:          return .clear
        }
    }
}

// MARK: - Metric tile
private struct MetricTile: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(Theme.monoDigit(size: 22))
                .foregroundStyle(Theme.labelPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

// MARK: - Live timeline Swift Charts view
private struct LiveTimelineChart: View {

    let points: [MonitorViewModel.TimelinePoint]

    private var visiblePoints: [MonitorViewModel.TimelinePoint] {
        Array(points.suffix(600))   // show last 10 min
    }

    var body: some View {
        Chart {
            ForEach(visiblePoints) { pt in
                AreaMark(
                    x: .value("Time", pt.time),
                    y: .value("dB", Double(AudioMath.normalisedLevel(pt.dBFS)))
                )
                .foregroundStyle(
                    pt.isSnoring
                    ? Theme.snoringGlow
                    : Theme.accentGlow
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(visiblePoints) { pt in
                if pt.isSnoring {
                    RuleMark(x: .value("Event", pt.time))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2]))
                        .foregroundStyle(Theme.snoring.opacity(0.4))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Theme.surfaceSecondary.opacity(0.9))
                AxisValueLabel(centered: true) {
                    if let t = value.as(Date.self) {
                        Text(t, format: .dateTime.hour(.defaultDigits(amPM: .narrow))
                            .minute(.twoDigits)
                            .second(.twoDigits))
                    }
                }
                .foregroundStyle(Theme.labelTertiary)
                .font(.caption2)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }
}
