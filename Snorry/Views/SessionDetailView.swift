import SwiftUI
import Charts
import AVFoundation

// MARK: - Detailed session replay screen
struct SessionDetailView: View {

    let session: SnoreSession
    @State private var vm: SessionDetailViewModel?

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            if let vm {
                ScrollView {
                    VStack(spacing: 20) {
                        statsCards(vm: vm)
                        timelineChart(vm: vm)
                        eventsList(vm: vm)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            } else {
                ProgressView().tint(Theme.accent)
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if vm == nil { vm = SessionDetailViewModel(session: session) }
        }
        .onDisappear { vm?.stopPlayback() }
    }

    // MARK: Stats row

    private func statsCards(vm: SessionDetailViewModel) -> some View {
        HStack(spacing: 12) {
            StatCard(label: "Duration",    value: vm.durationString,    icon: "clock")
            StatCard(label: "Events",      value: "\(session.eventCount)", icon: "waveform.badge.exclamationmark")
            StatCard(label: "Snoring",     value: vm.snorePercentString, icon: "zzz")
            if session.avgBRPM > 0 {
                StatCard(label: "Avg BRPM",
                         value: String(format: "%.0f", session.avgBRPM),
                         icon: "lungs")
            }
        }
    }

    // MARK: Timeline chart

    private func timelineChart(vm: SessionDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Timeline")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelSecondary)
                .padding(.horizontal, 4)

            if vm.waveformSamples.isEmpty {
                Text("No waveform data recorded.")
                    .font(.caption)
                    .foregroundStyle(Theme.labelTertiary)
                    .padding()
            } else {
                SessionTimelineChart(samples: vm.waveformSamples, events: vm.snoreEvents)
                    .frame(height: 160)
                    .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    // MARK: Events list

    private func eventsList(vm: SessionDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snore Events (\(vm.snoreEvents.count))")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelSecondary)

            if vm.snoreEvents.isEmpty {
                Text("No snore events detected this session.")
                    .font(.caption)
                    .foregroundStyle(Theme.labelTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(vm.snoreEvents) { event in
                    EventPlaybackRow(
                        event: event,
                        isPlaying: vm.playingEventID == event.id,
                        canReplay: event.playbackURL != nil,
                        onTap: { vm.togglePlayback(of: event) }
                    )
                }
                if let msg = vm.playbackDiagnostic {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(Theme.snoring)
                        .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }
}

// MARK: - Stat card
private struct StatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(Theme.monoDigit(size: 16))
                .foregroundStyle(Theme.labelPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.labelTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Session timeline (Swift Charts)
private struct SessionTimelineChart: View {

    let samples: [WaveformSample]
    let events: [SnoreEvent]

    var body: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(
                    x: .value("Time", s.timestamp),
                    y: .value("Level", Double(AudioMath.normalisedLevel(s.dBFS)))
                )
                .foregroundStyle(
                    s.isSnoringActive ? Theme.snoringGlow : Theme.accentGlow
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(samples.filter { $0.brpm > 0 }) { s in
                LineMark(
                    x: .value("Time", s.timestamp),
                    y: .value("BRPM", min(1.0, s.brpm / 60.0))
                )
                .foregroundStyle(Theme.accent.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            }

            // Vertical rule at each event start
            ForEach(events) { event in
                RuleMark(x: .value("Event", event.startDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    .foregroundStyle(Theme.snoring.opacity(0.5))
                    .annotation(position: .top, alignment: .leading) {
                        Image(systemName: "zzz")
                            .font(.system(size: 7))
                            .foregroundStyle(Theme.snoring)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.surfaceSecondary)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(Theme.labelTertiary)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
    }
}

// MARK: - Event playback row
struct EventPlaybackRow: View {

    let event: SnoreEvent
    let isPlaying: Bool
    /// False when no file exists — avoids a tappable UI that silently does nothing.
    let canReplay: Bool
    let onTap: () -> Void

    private var timeString: String {
        event.startDate.formatted(date: .omitted, time: .standard)
    }

    private var durationString: String {
        guard let d = event.duration else { return "—" }
        return String(format: "%.0fs", d)
    }

    /// The harmonic frequency stored at event-end — identical to the red marker
    /// shown on the Live Power Spectrum during monitoring. Nil when not captured.
    private var rumbleHz: Double? {
        event.rumbleFrequencyHz > 0 ? event.rumbleFrequencyHz : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onTap) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isPlaying ? Theme.snoring : Theme.accent)
                        .animation(.spring(duration: 0.3), value: isPlaying)
                }
                .disabled(!canReplay)
                .opacity(canReplay ? 1.0 : 0.3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timeString)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.labelPrimary)

                    HStack(spacing: 10) {
                        Label(durationString, systemImage: "clock.badge")
                            .font(.caption)
                            .foregroundStyle(Theme.labelSecondary)

                        if event.brpm > 0 {
                            Label(String(format: "%.0f BRPM", event.brpm), systemImage: "lungs")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }

                        Label(String(format: "%.0f dB", event.peakDB), systemImage: "speaker.wave.2")
                            .font(.caption)
                            .foregroundStyle(Theme.labelSecondary)
                    }
                }

                Spacer()

                if isPlaying {
                    PlayingIndicator()
                }
            }

            // Metric bars — shown when any meaningful data was captured for this event.
            if event.brpm > 0 || event.avgDB > -160 {
                VStack(spacing: 5) {
                    // BRPM bar: normalised over the physiological 10–60 BRPM range.
                    if event.brpm > 0 {
                        EventMetricBar(
                            label: "BRPM",
                            value: String(format: "%.0f", event.brpm),
                            fill: (event.brpm - 10) / 50,
                            color: Theme.accent
                        )
                    }

                    // Snore rumble: harmonic captured from the live spectrum during monitoring.
                    // Log-scale bar centred at 80 Hz (range 20–320 Hz, 20×320 = 80²).
                    if let rumbleFreq = rumbleHz {
                        let logFill = log(rumbleFreq / 20) / log(320.0 / 20)
                        EventMetricBar(
                            label: "Rumble",
                            value: String(format: "%.0f Hz", rumbleFreq),
                            fill: logFill,
                            color: Theme.snoring
                        )
                    }

                    // Average snore volume: normalised −60 dBFS (quiet) → −10 dBFS (loud).
                    if event.avgDB > -160 {
                        EventMetricBar(
                            label: "Avg Vol",
                            value: String(format: "%.0f dB", event.avgDB),
                            fill: Double((event.avgDB + 60) / 50),
                            color: Theme.good
                        )
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Metric bar indicator

private struct EventMetricBar: View {
    let label: String
    let value: String
    let fill: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
                Spacer()
                Text(value)
                    .font(Theme.monoDigit(size: 10))
                    .foregroundStyle(color.opacity(0.85))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.55), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fill))))
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Animated playing indicator
private struct PlayingIndicator: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.snoring)
                    .frame(width: 3, height: phase ? CGFloat([8, 14, 10][i]) : 4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(i) * 0.13),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
