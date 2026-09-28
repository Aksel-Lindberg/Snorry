import SwiftUI
import AVFoundation

// MARK: - Detailed session replay screen
struct SessionDetailView: View {

    let session: SnoreSession
    @State private var vm: SessionDetailViewModel?

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    statsCards
                    if let vm {
                        watchSnoreCard(vm: vm)
                        if let alertCard = AlertSetupSummaryCard.forSession(session) {
                            alertCard
                        }
                        eventsList(vm: vm)
                    } else {
                        if let alertCard = AlertSetupSummaryCard.forSession(session) {
                            alertCard
                        }
                        eventsLoadingPlaceholder
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(session.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .task(id: session.id) {
            vm = await SessionDetailViewModel.prepare(session: session)
        }
        .onDisappear {
            vm?.tearDownPlayback()
            AppReviewPrompter.requestReviewIfPendingAfterSessionDetail()
        }
    }

    // MARK: Stats row

    /// Rolled-up session fields render immediately; event sorting loads on the next turn.
    private var statsCards: some View {
        HStack(alignment: .top, spacing: 12) {
            StatCard(label: "Sleep duration", value: session.displayDurationSummary, icon: "clock")
            StatCard(label: "Snore events", value: "\(session.displayEventCount)", icon: "waveform.badge.exclamationmark")
            StatCard(label: "Snore duration", value: session.displayTotalSnoreTime, icon: "zzz")
        }
    }

    private var eventsLoadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text("Loading sound events…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    // MARK: Watch snore card

    private func watchSnoreCard(vm: SessionDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text("Snore Clock")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)

                Spacer(minLength: 0)

                snoreClockLegend
            }
            .padding(.horizontal, 4)

            SnoreWatchFace(events: vm.snoreEvents)
                .frame(height: 220)

            if vm.snoreEvents.isEmpty {
                Text("No snore events recorded this session")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    /// Snore Clock legend — one line when space allows; otherwise breaks after "time".
    private var snoreClockLegend: some View {
        ViewThatFits(in: .horizontal) {
            Text("Arc position = time    length = duration")
                .font(.footnote)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .lineLimit(1)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Arc position = time")
                Text("length = duration")
            }
            .font(.footnote)
            .foregroundStyle(Theme.labelOnSurfaceSecondary)
            .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Events list

    private func eventsList(vm: SessionDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sound Events (\(vm.allCompletedEvents.count))")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                if vm.allCompletedEvents.count > vm.snoreEvents.count {
                    Text("\(vm.snoreEvents.count) snoring")
                        .font(.caption)
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                }
            }

            if let summary = EventMetricScale.nightLoudness(samples: vm.allCompletedEvents.map {
                EventMetricScale.LoudnessSample(
                    peakDB: $0.peakDB,
                    avgDB: $0.avgDB,
                    duration: $0.duration ?? 0
                )
            }) {
                nightLoudnessSummary(summary)
            }

            if vm.allCompletedEvents.isEmpty {
                Text("No sound events detected this session.")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    .padding(.vertical, 8)
            } else {
                // Same relative scale as Sleep History: longest bout in this list = full bar.
                let maxEventDuration = vm.allCompletedEvents.compactMap(\.duration).max() ?? 0
                let loudnessSamples = vm.allCompletedEvents.map {
                    EventMetricScale.LoudnessSample(
                        peakDB: $0.peakDB,
                        avgDB: $0.avgDB,
                        duration: $0.duration ?? 0
                    )
                }
                let loudestPeakIndex = EventMetricScale.indexOfLoudestPeak(in: loudnessSamples)
                ForEach(Array(vm.allCompletedEvents.enumerated()), id: \.element.id) { index, event in
                    EventPlaybackRow(
                        event: event,
                        maxEventDuration: maxEventDuration,
                        isNightLoudest: loudestPeakIndex == index,
                        isPlaying: vm.playingEventID == event.id,
                        isPreparing: vm.preparingEventID == event.id,
                        canReplay: vm.showsPlaybackChrome(for: event),
                        onTap: { vm.togglePlayback(of: event) },
                        onShare: { AppAnalytics.logSnoreClipShared() }
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

    /// Loudest peak and duration-weighted average for the bouts in this list.
    private func nightLoudnessSummary(_ summary: EventMetricScale.NightLoudnessSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                loudnessStat(title: "Loudest", word: summary.loudest)
                loudnessStat(title: "Average", word: summary.average)
            }
            Text(EventMetricScale.loudnessScaleCaption)
                .font(.caption2)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loudnessStat(title: String, word: EventMetricScale.LoudnessWord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
            Text(word.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.labelPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(word.title)")
    }
}

// MARK: - Snore watch face

/// Draws a 12-hour clock face with arc segments on the bezel for each snore event.
/// Arc *position* encodes the real wall-clock start time; arc *length* encodes event duration
/// as a fraction of one 12-hour dial turn (same scale as the hour hand).
private struct SnoreWatchFace: View {

    let events: [SnoreEvent]
    @Environment(\.colorScheme) private var colorScheme

    /// Seconds represented by one full revolution of the 12-hour dial.
    private static let dialSeconds: Double = 12 * 3600

    var body: some View {
        // Pre-compute start angles + durations outside the Canvas closure so we only
        // capture plain value types (avoids Sendable issues with SwiftData models).
        let arcData: [(startDeg: Double, duration: TimeInterval)] = events.compactMap { event in
            guard let duration = event.duration, duration > 0 else { return nil }
            let comps = Calendar.current.dateComponents([.hour, .minute, .second],
                                                        from: event.startDate)
            // Map real clock time onto 12-hour dial (0° = top, clockwise)
            let totalSec = Double((comps.hour ?? 0) % 12) * 3600
                         + Double(comps.minute ?? 0) * 60
                         + Double(comps.second ?? 0)
            let startDeg = (totalSec / Self.dialSeconds) * 360.0
            return (startDeg, duration)
        }

        // Capture chrome colours before the @Sendable Canvas closure.
        // White-on-dark opacities vanish on light cards; ink follows labelPrimary.
        let isDark = colorScheme == .dark
        let ink = Theme.labelPrimary
        let bezelColor = ink.opacity(isDark ? 0.22 : 0.32)
        let trackColor = ink.opacity(isDark ? 0.06 : 0.12)
        let faceFillColor: Color = isDark ? Color.white.opacity(0.04) : Theme.surfaceSecondary
        let faceStrokeColor = ink.opacity(isDark ? 0.15 : 0.28)
        let majorTickColor = ink.opacity(isDark ? 0.55 : 0.58)
        let minorTickColor = ink.opacity(isDark ? 0.18 : 0.28)
        let hourLabelColor = ink.opacity(isDark ? 0.45 : 0.62)
        let centerDotColor = ink.opacity(isDark ? 0.40 : 0.50)
        let arcColor = Theme.snoring.opacity(isDark ? 0.88 : 1.0)

        Canvas { ctx, size in
            let dim    = min(size.width, size.height)
            let cx     = size.width  / 2
            let cy     = size.height / 2

            // — Radii —
            let outerR = dim * 0.46    // decorative outer ring
            let arcR   = dim * 0.42    // centre-line of the snore-arc track
            #if DEBUG
            let marketingArcs = AppStoreDemoSeeder.showsMarketingChrome
            #else
            let marketingArcs = false
            #endif
            let arcW   = dim * (marketingArcs ? 0.072 : 0.055)
            let faceR  = dim * 0.365   // inner face boundary

            // — Outer bezel ring —
            var bezel = Path()
            bezel.addEllipse(in: CGRect(x: cx - outerR, y: cy - outerR,
                                        width: outerR * 2, height: outerR * 2))
            ctx.stroke(bezel, with: .color(bezelColor), lineWidth: 2)

            // — Subtle arc-track guide (thin ring where arcs will appear) —
            var track = Path()
            track.addEllipse(in: CGRect(x: cx - arcR, y: cy - arcR,
                                        width: arcR * 2, height: arcR * 2))
            ctx.stroke(track, with: .color(trackColor), lineWidth: arcW)

            // — Watch face background —
            var face = Path()
            face.addEllipse(in: CGRect(x: cx - faceR, y: cy - faceR,
                                       width: faceR * 2, height: faceR * 2))
            ctx.fill(face, with: .color(faceFillColor))
            ctx.stroke(face, with: .color(faceStrokeColor), lineWidth: 1.5)

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
                           with: .color(isMajor ? majorTickColor : minorTickColor),
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
                        .foregroundStyle(hourLabelColor),
                    at: CGPoint(x: cx + cos(rad) * labelR,
                                y: cy + sin(rad) * labelR)
                )
            }

            // — Centre dot —
            var dot = Path()
            dot.addEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
            ctx.fill(dot, with: .color(centerDotColor))

            // — Snore event arcs —
            // Sweep angle is strictly proportional to duration / 12h (no minimum sweep:
            // a 4° floor made 2s snores look like ~8 minutes). Butt caps keep thick strokes
            // from extending past the true angle the way round caps do.
            for arc in arcData {
                let proportionalSweep = (arc.duration / Self.dialSeconds) * 360.0
                let minSweep = marketingArcs ? 3.0 : 0.0
                let sweepDeg = max(minSweep, proportionalSweep)
                guard sweepDeg > 1e-6 else { continue }
                var p = Path()
                p.addArc(center: CGPoint(x: cx, y: cy),
                         radius: arcR,
                         startAngle: .degrees(arc.startDeg - 90.0),
                         endAngle:   .degrees(arc.startDeg - 90.0 + sweepDeg),
                         clockwise: false)
                ctx.stroke(p,
                           with: .color(arcColor),
                           style: StrokeStyle(lineWidth: arcW, lineCap: .butt))
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
            Text(formattedLabel)
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Two-word labels split onto two lines so all stat tiles share the same height.
    private var formattedLabel: String {
        let parts = label.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return label }
        return "\(parts[0])\n\(parts[1])"
    }
}

// MARK: - Event playback row
struct EventPlaybackRow: View {

    let event: SnoreEvent
    /// Longest bout in this session list — duration bars are relative to this, like Sleep History.
    let maxEventDuration: TimeInterval
    /// True for the bout whose peak reached the night’s highest level.
    var isNightLoudest: Bool = false
    let isPlaying: Bool
    let isPreparing: Bool
    /// False when no file exists — avoids a tappable UI that silently does nothing.
    let canReplay: Bool
    let onTap: () -> Void
    var onShare: (() -> Void)? = nil

    private var timeString: String {
        event.startDate.formatted(date: .omitted, time: .standard)
    }

    private var durationString: String {
        guard let d = event.duration else { return "—" }
        return String(format: "%.0fs", d)
    }

    private var rowLoudness: EventMetricScale.RowLoudness? {
        EventMetricScale.rowLoudness(avgDB: event.avgDB, peakDB: event.peakDB)
    }

    private var durationFill: CGFloat {
        CGFloat(EventMetricScale.durationFill(
            duration: event.duration ?? 0,
            maxDuration: maxEventDuration
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onTap) {
                    Group {
                        if isPreparing {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(Theme.accent)
                        } else {
                            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(isPlaying ? Theme.snoring : Theme.accent)
                                .animation(.spring(duration: 0.3), value: isPlaying)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .disabled(!canReplay && !isPreparing)
                .opacity(canReplay || isPreparing ? 1.0 : 0.3)
                .accessibilityLabel(
                    isPreparing ? "Preparing audio" : (isPlaying ? "Stop playback" : "Play recording")
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(timeString)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.labelPrimary)
                        if isNightLoudest {
                            Text("Loudest")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.snoring)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.snoring.opacity(0.14), in: Capsule())
                                .accessibilityLabel("Loudest moment this night")
                        }
                    }
                    if isPreparing {
                        Text("Preparing audio…")
                            .font(.caption)
                            .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    } else {
                        SoundKindBadge(kind: event.soundKind)
                    }
                }

                Spacer()

                if canReplay {
                    SnoreClipShareButton(event: event, onShare: onShare)
                }

                if isPlaying {
                    PlayingIndicator()
                }
            }

            if event.duration != nil || rowLoudness != nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if event.duration != nil {
                            Label("Duration", systemImage: "clock.badge")
                                .font(.caption)
                                .foregroundStyle(Theme.labelOnSurfaceSecondary)

                            Text(durationString)
                                .font(Theme.monoDigit(size: 12, weight: .medium))
                                .foregroundStyle(Theme.labelPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 8)

                        if let rowLoudness {
                            loudnessLine(rowLoudness)
                        }
                    }

                    if event.duration != nil {
                        durationBar
                            .accessibilityLabel("Event duration relative to the longest bout this night")
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func loudnessLine(_ rowLoudness: EventMetricScale.RowLoudness) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.wave.2")
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)

            if let louderPeak = rowLoudness.louderPeak {
                Text("Avg")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                Text(rowLoudness.average.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.labelPrimary)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                Text("Peak")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
                Text(louderPeak.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.snoring)
            } else {
                Text(rowLoudness.average.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.labelPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLoudness.accessibilityLabel)
    }

    /// Same visual language as Sleep History session rows: coral bar vs the longest item in view.
    private var durationBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.surfaceSecondary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.snoringGradient)
                    .frame(width: max(geo.size.width * durationFill, durationFill > 0 ? 8 : 0))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Event metric scale

/// Shared fill math and loudness words for the Sound Events card. Kept free of SwiftUI so unit tests can cover it.
nonisolated enum EventMetricScale {
    /// Stored level when a bout has no usable reading.
    static let missingLevelDB: Float = -160

    /// Caption under the night loudness summary tiles.
    static let loudnessScaleCaption =
        "How loud this iPhone heard these sounds. Soft, Moderate, Loud, Very loud."

    /// Plain-language loudness for a dBFS reading. Nil when the reading is missing.
    /// Bands match levels Snorry actually records on an iPhone microphone.
    enum LoudnessWord: String, Equatable, Sendable {
        case soft
        case moderate
        case loud
        case veryLoud

        var title: String {
            switch self {
            case .soft:     return "Soft"
            case .moderate: return "Moderate"
            case .loud:     return "Loud"
            case .veryLoud: return "Very loud"
            }
        }

        /// Higher means a louder band on the iPhone microphone scale.
        var severity: Int {
            switch self {
            case .soft:     return 0
            case .moderate: return 1
            case .loud:     return 2
            case .veryLoud: return 3
            }
        }
    }

    /// Average and optional louder peak for one bout row.
    struct RowLoudness: Equatable, Sendable {
        var average: LoudnessWord
        /// Set only when the peak band is louder than the average band.
        var louderPeak: LoudnessWord?

        var accessibilityLabel: String {
            if let louderPeak {
                return "Average loudness \(average.title), peak \(louderPeak.title)"
            }
            return "Loudness \(average.title)"
        }
    }

    /// One bout’s levels, without pulling in the SwiftData model.
    struct LoudnessSample: Equatable, Sendable {
        var peakDB: Float
        var avgDB: Float
        var duration: TimeInterval
    }

    /// Loudest peak and duration-weighted average for the events shown in the list.
    struct NightLoudnessSummary: Equatable, Sendable {
        var loudest: LoudnessWord
        var average: LoudnessWord
    }

    /// Linear fill against the longest bout in the current session list.
    /// A 10-minute absolute range made typical 10–50 s snores look empty next to volume.
    static func durationFill(duration: TimeInterval, maxDuration: TimeInterval) -> Double {
        guard duration > 0, maxDuration > 0 else { return 0 }
        return min(1, duration / maxDuration)
    }

    /// Maps dBFS onto Soft / Moderate / Loud / Very loud. Quieter than or equal to −50 is Soft.
    static func loudnessWord(dBFS: Float) -> LoudnessWord? {
        guard dBFS > missingLevelDB else { return nil }
        if dBFS > -30 { return .veryLoud }
        if dBFS > -40 { return .loud }
        if dBFS > -50 { return .moderate }
        return .soft
    }

    /// Row labels from average and peak dBFS. Peak is omitted when it falls in the same band as average.
    static func rowLoudness(avgDB: Float, peakDB: Float) -> RowLoudness? {
        guard let average = loudnessWord(dBFS: avgDB) else { return nil }
        guard peakDB > missingLevelDB, let peak = loudnessWord(dBFS: peakDB) else {
            return RowLoudness(average: average, louderPeak: nil)
        }
        if peak.severity > average.severity {
            return RowLoudness(average: average, louderPeak: peak)
        }
        return RowLoudness(average: average, louderPeak: nil)
    }

    /// Index of the bout with the highest peak dBFS. On a tie, the earliest bout wins.
    static func indexOfLoudestPeak(in samples: [LoudnessSample]) -> Int? {
        var bestIndex: Int?
        var bestPeak = missingLevelDB
        for (index, sample) in samples.enumerated() {
            guard sample.peakDB > missingLevelDB else { continue }
            if sample.peakDB > bestPeak {
                bestPeak = sample.peakDB
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Night summary from the bouts in the Sound Events list. Nil when none have a real level.
    static func nightLoudness(samples: [LoudnessSample]) -> NightLoudnessSummary? {
        guard let loudestDB = samples.map(\.peakDB).filter({ $0 > missingLevelDB }).max(),
              let loudest = loudnessWord(dBFS: loudestDB),
              let averageDB = durationWeightedAverageDB(samples: samples),
              let average = loudnessWord(dBFS: averageDB) else { return nil }
        return NightLoudnessSummary(loudest: loudest, average: average)
    }

    /// Weights each bout by its duration. Falls back to an unweighted mean when every duration is zero.
    static func durationWeightedAverageDB(samples: [LoudnessSample]) -> Float? {
        let valid = samples.filter { $0.avgDB > missingLevelDB }
        guard !valid.isEmpty else { return nil }
        let totalWeight = valid.reduce(0.0) { $0 + max($1.duration, 0) }
        if totalWeight > 0 {
            let sum = valid.reduce(0.0) { $0 + Double($1.avgDB) * max($1.duration, 0) }
            return Float(sum / totalWeight)
        }
        let sum = valid.reduce(0.0) { $0 + Double($1.avgDB) }
        return Float(sum / Double(valid.count))
    }
}

// MARK: - Sound kind badge

/// Small inline label showing the classification category for a detected bout.
/// Hidden when the kind is `.snoring` and the session had no background period,
/// so foreground-only nights look identical to pre-feature behaviour.
private struct SoundKindBadge: View {

    let kind: SoundEventKind

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.systemImage)
            Text(kind.displayName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(foregroundColor.opacity(0.12), in: Capsule())
    }

    private var foregroundColor: Color {
        switch kind {
        case .snoring:      return Theme.snoring
        case .sleepTalking: return Theme.accent
        case .environment:  return Theme.labelTertiary
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
