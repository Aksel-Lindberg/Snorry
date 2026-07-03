import SwiftUI
import Charts

// MARK: - Live recording session screen
struct MonitorView: View {

    @Bindable var vm: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(UserPreferences.displayNameKey) private var userDisplayName = ""

    @State private var pulseAnimation = false
    @State private var showSpectrumInfo = false

    /// Vertical gap between status, spectrum, metrics, and timeline cards.
    private var cardStackSpacing: CGFloat {
        horizontalSizeClass == .regular ? 20 : 12
    }

    /// Visible gap between Stop Recording and the bottom safe area (tab bar hidden on this screen).
    private var stopButtonBottomGap: CGFloat {
        horizontalSizeClass == .regular ? 28 : 20
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 28 : 16
    }

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: cardStackSpacing) {
                    greetingHeader
                    statusBadge
                    spectrumCard
                    metricsRow
                    alertPhaseCard
                    timelineCard
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .allowsHitTesting(!vm.isStoppingMonitoring)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                stopButton
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, stopButtonBottomGap)
                    .background(
                        Theme.background.opacity(0.92)
                            .ignoresSafeArea(edges: .bottom)
                    )
            }

            if vm.isStoppingMonitoring {
                stoppingOverlay
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Dismiss whenever recording stops (button tap or external cause)
        .onChange(of: vm.isMonitoring) { _, monitoring in
            if !monitoring { dismiss() }
        }
        .sheet(isPresented: $showSpectrumInfo) {
            LiveSpectrumInfoSheet()
        }
    }

    // MARK: Sub-views

    private var greetingHeader: some View {
        VStack(spacing: 6) {
            Text(UserPreferences.goodNightGreeting(displayName: userDisplayName))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.labelPrimary)
                .multilineTextAlignment(.center)

            Text("We're listening for snores")
                .font(Theme.handwritten(size: horizontalSizeClass == .regular ? 17 : 19))
                .foregroundStyle(Theme.handwrittenGradient)
                .multilineTextAlignment(.center)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

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
            HStack(alignment: .center, spacing: 8) {
                Text("Live Power Spectrum")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)

                Spacer(minLength: 0)

                Button {
                    showSpectrumInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Live power spectrum info")
                .accessibilityHint("Opens technical details about the frequency view")
            }

            Text("Frequency view of tonight’s audio")
                .font(.caption2)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LivePowerSpectrumView(
                bands: vm.spectrumBands,
                isSnoring: vm.detectionPhase == .confirmed && vm.isSnoring,
                brpmHighlightBandIndex: vm.spectrumBRPMHighlightBandIndex,
                brpmHarmonicFrequencyHz: vm.spectrumBRPMHighlightHz,
                emphasiseMarker: vm.detectionPhase == .confirmed && vm.isSnoring
            )
            .frame(height: 104)

            HStack(alignment: .firstTextBaseline) {
                Text("45 Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                Spacer()
                if let hz = vm.spectrumBRPMHighlightHz, vm.detectionPhase == .confirmed, vm.brpmAvailable {
                    Text(String(format: "~%.0f Hz harmonic", hz))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.red.opacity(vm.isSnoring ? 1 : 0.65))
                }
                Spacer()
                Text("\(nyquistLabel) Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
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
                value: vm.currentDB > -160 ? String(format: "%.0f", vm.currentDB) : "—"
            ) {
                LoudnessVisualizerIcon(
                    dBFS: vm.currentDB,
                    color: Theme.accent
                )
            }
            MetricTile(
                label: "BRPM",
                value: vm.brpmAvailable ? String(format: "%.0f", vm.currentBRPM) : "—"
            ) {
                BreathingLungsIcon(
                    brpm: vm.currentBRPM,
                    isActive: vm.isSnoreEventActive && vm.brpmAvailable,
                    color: Theme.snoring
                )
            }
            MetricTile(
                label: "Events",
                value: "\(vm.snoreEventCount)"
            ) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(Theme.good)
            }
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
            Task {
                await vm.stopMonitoringAsync()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                Text(vm.isStoppingMonitoring ? "Stopping…" : "Stop Recording")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.stopGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        }
        .disabled(vm.isStoppingMonitoring)
        .accessibilityLabel("Stop recording")
        .accessibilityHint("Ends the session and saves to Sleep History")
    }

    private var stoppingOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)
                Text("Saving session…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                Text(vm.stoppingStatusMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: vm.stoppingStatusMessage)
            }
            .padding(26)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .strokeBorder(Theme.surfaceSecondary.opacity(0.9), lineWidth: 1)
            )
            .padding(.horizontal, 36)
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: vm.isStoppingMonitoring)
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
        case .alarming:  return "speaker.wave.3.fill"
        default:         return "bell"
        }
    }

    private var alertTitle: String {
        switch vm.alertPhase {
        case .notified:   return "Push notification sent"
        case .alarming:   return "Alarm active"
        case .cleared:    return "Alert Cleared"
        default:          return ""
        }
    }

    private var alertSubtitle: String {
        switch vm.alertPhase {
        case .notified:   return "Check your iPhone notification."
        case .alarming:   return "Volume rises every 2 s. Stops when snoring ends."
        case .cleared:    return "Snoring stopped."
        default:          return ""
        }
    }

    private var alertColor: Color {
        switch vm.alertPhase {
        case .notified:   return .yellow
        case .alarming:   return Theme.snoring
        case .cleared:    return Theme.good
        default:          return .clear
        }
    }
}

// MARK: - Metric tile
private struct MetricTile: View {
    let label: String
    let value: String
    @ViewBuilder let iconView: () -> AnyView

    init(label: String, value: String, @ViewBuilder iconView: @escaping () -> some View) {
        self.label = label
        self.value = value
        self.iconView = { AnyView(iconView()) }
    }

    var body: some View {
        VStack(spacing: 6) {
            iconView()
                .frame(height: 22)

            Text(value)
                .font(Theme.monoDigit(size: 22))
                .foregroundStyle(Theme.labelPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

private struct LoudnessVisualizerIcon: View {
    let dBFS: Float
    let color: Color

    /// Maps live dBFS to a stable 0...1 value used by the bar animation.
    private var level: CGFloat {
        CGFloat(AudioMath.normalisedLevel(dBFS))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.2) {
                ForEach(0..<6, id: \.self) { index in
                    // Per-bar phase offsets create a rolling "equalizer" motion.
                    let phase = t * 5.0 + Double(index) * 0.65
                    let wave = (sin(phase) + 1) * 0.5
                    let floor = max(0.14, level * 0.33)
                    let height = 4 + 16 * max(floor, level * CGFloat(0.55 + 0.45 * wave))
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(color.opacity(0.55 + 0.45 * level))
                        .frame(width: 3, height: height)
                }
            }
            .frame(width: 30, height: 22, alignment: .bottom)
            .drawingGroup()
        }
    }
}

private struct BreathingLungsIcon: View {
    let brpm: Double
    let isActive: Bool
    let color: Color

    private var clampedBRPM: Double {
        min(max(brpm, 6), 40)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period = 60.0 / clampedBRPM
            // One full inhale/exhale per BRPM cycle.
            let cycle = 0.5 + 0.5 * sin((2.0 * .pi * t) / period)
            let breathScale = isActive ? (0.88 + 0.16 * cycle) : 0.92

            HStack(spacing: 4) {
                Capsule()
                    .fill(color.opacity(isActive ? 0.95 : 0.45))
                    .frame(width: 9, height: 14)
                    .scaleEffect(x: breathScale, y: 1.0, anchor: .bottomTrailing)

                Capsule()
                    .fill(color.opacity(isActive ? 0.95 : 0.45))
                    .frame(width: 9, height: 14)
                    .scaleEffect(x: breathScale, y: 1.0, anchor: .bottomLeading)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(isActive ? 0.95 : 0.45))
                    .frame(width: 2.4, height: 7)
                    .offset(y: -5)
            }
            .frame(width: 30, height: 22)
            .drawingGroup()
        }
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
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .font(.caption2)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }
}
