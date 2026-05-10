import SwiftUI
import SwiftData
import Charts
import AVFoundation
import UserNotifications

// MARK: - Detailed session replay screen
struct SessionDetailView: View {

    let session: SnoreSession
    @Environment(\.modelContext) private var modelContext
    @Query private var alertSettingsRows: [AlertSettings]
    @State private var vm: SessionDetailViewModel?
    @State private var notificationsAuthorized = false

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            if let vm {
                ScrollView {
                    VStack(spacing: 20) {
                        statsCards(vm: vm)
                        watchSnoreCard(vm: vm)
                        if let settings = alertSettingsRows.first {
                            AlertSetupSummaryCard(
                                settings: settings,
                                notificationsAuthorized: notificationsAuthorized,
                                caption: "Current preferences · same as Monitor tab"
                            )
                        }
                        timelineChart(vm: vm)
                        eventsList(vm: vm)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.accent)
                    Text("Loading session…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            ensureAlertSettingsRowExists()
        }
        .task(id: session.id) {
            vm = await SessionDetailViewModel.prepare(session: session, modelContext: modelContext)
        }
        .task {
            let status = await NotificationManager.shared.checkAuthorisationStatus()
            notificationsAuthorized = (status == .authorized)
        }
        .onDisappear { vm?.stopPlayback() }
    }

    private func ensureAlertSettingsRowExists() {
        guard alertSettingsRows.isEmpty else { return }
        _ = AlertSettings.load(context: modelContext)
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

    // MARK: Watch snore card

    private func watchSnoreCard(vm: SessionDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Snore Clock")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.labelSecondary)
                Spacer()
                Text("Arc position = time  ·  length = duration")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
            }
            .padding(.horizontal, 4)

            SnoreWatchFace(events: vm.snoreEvents)
                .frame(height: 220)

            if vm.snoreEvents.isEmpty {
                Text("No snore events recorded this session")
                    .font(.caption)
                    .foregroundStyle(Theme.labelTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    // MARK: Timeline chart

    private func timelineChart(vm: SessionDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Timeline")
                .font(.caption.bold())
                .foregroundStyle(Theme.labelSecondary)
                .padding(.horizontal, 4)

            if vm.chartTimelinePoints.isEmpty {
                Text("No waveform data recorded.")
                    .font(.caption)
                    .foregroundStyle(Theme.labelTertiary)
                    .padding()
            } else {
                SessionTimelineChart(samples: vm.chartTimelinePoints, events: vm.snoreEvents)
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

// MARK: - Snore watch face

/// Draws a 12-hour clock face with red arc segments on the bezel for each snore event.
/// Arc *position* encodes the real wall-clock start time; arc *length* encodes event duration.
private struct SnoreWatchFace: View {

    let events: [SnoreEvent]

    /// Seconds in a full 12-hour dial rotation.
    private static let dialSeconds: Double = 12 * 3600
    /// Minimum visible sweep so very short events still appear as small arcs.
    private static let minSweepDeg: Double = 4.0

    var body: some View {
        // Pre-compute arc geometry outside the Canvas closure so we only
        // capture plain value types (avoids Sendable issues with SwiftData models).
        let arcData: [(startDeg: Double, sweepDeg: Double)] = events.compactMap { event in
            guard let duration = event.duration, duration > 0 else { return nil }
            let comps = Calendar.current.dateComponents([.hour, .minute, .second],
                                                        from: event.startDate)
            // Map real clock time onto 12-hour dial (0° = top, clockwise)
            let totalSec = Double((comps.hour ?? 0) % 12) * 3600
                         + Double(comps.minute ?? 0) * 60
                         + Double(comps.second ?? 0)
            let startDeg = (totalSec / Self.dialSeconds) * 360.0
            let sweepDeg = max(Self.minSweepDeg, (duration / Self.dialSeconds) * 360.0)
            return (startDeg, sweepDeg)
        }

        let snoringColor = Theme.snoring   // capture before entering @Sendable closure

        Canvas { ctx, size in
            let dim    = min(size.width, size.height)
            let cx     = size.width  / 2
            let cy     = size.height / 2

            // — Radii —
            let outerR = dim * 0.46    // decorative outer ring
            let arcR   = dim * 0.42    // centre-line of the snore-arc track
            let arcW   = dim * 0.055   // stroke width of each snore arc
            let faceR  = dim * 0.365   // inner face boundary

            // — Outer bezel ring —
            var bezel = Path()
            bezel.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR,
                                        width: outerR * 2, height: outerR * 2))
            ctx.stroke(bezel, with: .color(.white.opacity(0.22)), lineWidth: 2)

            // — Subtle arc-track guide (thin ring where arcs will appear) —
            var track = Path()
            track.addEllipse(in: CGRect(x: cx - arcR, y: cy - arcR,
                                        width: arcR * 2, height: arcR * 2))
            ctx.stroke(track, with: .color(.white.opacity(0.06)), lineWidth: arcW)

            // — Watch face background —
            var face = Path()
            face.addEllipse(in: CGRect(x: cx - faceR, y: cy - faceR,
                                       width: faceR * 2, height: faceR * 2))
            ctx.fill(face, with: .color(.white.opacity(0.04)))
            ctx.stroke(face, with: .color(.white.opacity(0.15)), lineWidth: 1.5)

            // — Tick marks: 12 major (hourly) + 48 minor (every 5 min) —
            for tick in 0..<60 {
                let isMajor = tick % 5 == 0
                let rad = (Double(tick) * 6.0 - 90.0) * .pi / 180.0
                let innerR = isMajor ? faceR * 0.81 : faceR * 0.91
                var t = Path()
                t.move(to: CGPoint(x: cx + cos(rad) * faceR * 0.97,
                                   y: cy + sin(rad) * faceR * 0.97))
                t.addLine(to: CGPoint(x: cx + cos(rad) * innerR,
                                      y: cy + sin(rad) * innerR))
                ctx.stroke(t,
                           with: .color(.white.opacity(isMajor ? 0.55 : 0.18)),
                           lineWidth: isMajor ? 1.5 : 0.8)
            }

            // — Hour labels at 12, 3, 6, 9 —
            let labelR = faceR * 0.62
            let hourLabels: [(hour: Int, label: String)] = [
                (0, "12"), (3, "3"), (6, "6"), (9, "9")
            ]
            for entry in hourLabels {
                let rad = (Double(entry.hour) * 30.0 - 90.0) * .pi / 180.0
                ctx.draw(
                    Text(entry.label)
                        .font(.system(size: dim * 0.055, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45)),
                    at: CGPoint(x: cx + cos(rad) * labelR,
                                y: cy + sin(rad) * labelR)
                )
            }

            // — Centre dot —
            var dot = Path()
            dot.addEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
            ctx.fill(dot, with: .color(.white.opacity(0.40)))

            // — Snore event arcs —
            // Each arc starts at the event's real clock position and sweeps clockwise
            // proportional to the event's duration. Wrap-around near 12/0° is handled
            // automatically because Path.addArc accepts angles beyond 360°.
            for arc in arcData {
                var p = Path()
                p.addArc(center: CGPoint(x: cx, y: cy),
                         radius: arcR,
                         startAngle: .degrees(arc.startDeg - 90.0),
                         endAngle:   .degrees(arc.startDeg - 90.0 + arc.sweepDeg),
                         clockwise: false)
                ctx.stroke(p,
                           with: .color(snoringColor.opacity(0.88)),
                           style: StrokeStyle(lineWidth: arcW, lineCap: .round))
            }
        }
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

    let samples: [TimelineChartPoint]
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

            // Inline label attached near the middle of the BRPM line, shown just below it.
            let brpmSamples = samples.filter { $0.brpm > 0 }
            if !brpmSamples.isEmpty {
                let labelSample = brpmSamples[brpmSamples.count / 2]
                PointMark(
                    x: .value("Time", labelSample.timestamp),
                    y: .value("BRPM", min(1.0, labelSample.brpm / 60.0))
                )
                .symbolSize(0)
                .annotation(position: .bottom, spacing: 4) {
                    Text("BRPM trend")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceSecondary.opacity(0.9), in: Capsule())
                }
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

    /// Duration normalised to a 5 s ... 10 min range for card bar visualisation.
    private var durationFill: Double? {
        guard let duration = event.duration else { return nil }
        let minSeconds = 5.0
        let maxSeconds = 600.0
        return (duration - minSeconds) / (maxSeconds - minSeconds)
    }

    /// Strongest rumble-band frequency: **measured from the clip** when `spectralPeakHz` is set;
    /// otherwise the legacy breath-tempo harmonic (~85 Hz) from older sessions.
    private var rumbleDisplayHz: Double? {
        if event.spectralPeakHz > 0 { return event.spectralPeakHz }
        if event.rumbleFrequencyHz > 0 { return event.rumbleFrequencyHz }
        return nil
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

                HStack(spacing: 10) {
                    Text(timeString)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.labelPrimary)
                }

                Spacer()

                if isPlaying {
                    PlayingIndicator()
                }
            }

            // Metric bars — shown when duration and/or other measurements were captured for this event.
            if durationFill != nil || event.brpm > 0 || event.avgDB > -160
                || event.spectralPeakHz > 0 || event.rumbleFrequencyHz > 0 {
                VStack(spacing: 5) {
                    // Snore duration: mapped from 5 s (0%) to 10 min (100%).
                    if let durationFill {
                        EventMetricBar(
                            label: "Duration",
                            value: durationString,
                            fill: durationFill,
                            color: Theme.labelSecondary,
                            systemImage: "clock.badge"
                        )
                    }

                    // BRPM bar: normalised over the physiological 10–60 BRPM range.
                    if event.brpm > 0 {
                        EventMetricBar(
                            label: "BRPM",
                            value: String(format: "%.0f", event.brpm),
                            fill: (event.brpm - 10) / 50,
                            color: Theme.accent,
                            systemImage: "lungs"
                        )
                    }

                    // Rumble: dominant FFT peak in the snore band from the recording (new);
                    // older rows fall back to breath harmonic. Log-scale bar 50–2000 Hz.
                    if let rumbleFreq = rumbleDisplayHz {
                        let lo = 50.0
                        let hi = 2000.0
                        let clamped = min(max(rumbleFreq, lo), hi)
                        let logFill = log(clamped / lo) / log(hi / lo)
                        let rumbleLabel = event.spectralPeakHz > 0 ? "Rumble" : "Breath harmonic"
                        EventMetricBar(
                            label: rumbleLabel,
                            value: String(format: "%.0f Hz", rumbleFreq),
                            fill: logFill,
                            color: Theme.snoring,
                            systemImage: "waveform.path.ecg"
                        )
                    }

                    // Average snore volume: −80 dBFS → 0%, −55 dBFS → 50%, −30 dBFS → 100%.
                    if event.avgDB > -160 {
                        EventMetricBar(
                            label: "Avg Vol",
                            value: String(format: "%.0f dB", event.avgDB),
                            fill: Double((event.avgDB + 80) / 50),
                            color: Theme.good,
                            systemImage: "speaker.wave.2"
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
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let systemImage {
                Label(label, systemImage: systemImage)
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
            } else {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
            }

            GeometryReader { geo in
                ZStack {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.12))

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.45), color.opacity(0.80)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fill))),
                               height: geo.size.height)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Value centred on the bar
                    Text(value)
                        .font(Theme.monoDigit(size: 10))
                        .foregroundStyle(.white.opacity(0.90))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
