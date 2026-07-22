import SwiftUI
import Charts
import SwiftData

// MARK: - Insights tab root (lazy-initialises the view model)
struct AnalyticsView: View {

    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm: AnalyticsViewModel?
    @State private var showSubscription = false

    private var hasPremiumAccess: Bool { appEnv.subscription.hasPremiumAccess }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                if hasPremiumAccess {
                    if let vm {
                        AnalyticsContent(vm: vm)
                    } else {
                        ProgressView().tint(Theme.accent)
                    }
                } else {
                    AnalyticsLockedView {
                        AppAnalytics.logPaywallViewed(source: "insights_tab")
                        showSubscription = true
                    }
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .onAppear {
                guard hasPremiumAccess else { return }
                if vm == nil { vm = AnalyticsViewModel(context: context) }
                vm?.refresh()
            }
            .onChange(of: hasPremiumAccess) { _, isPremium in
                guard isPremium else {
                    vm = nil
                    return
                }
                if vm == nil { vm = AnalyticsViewModel(context: context) }
                vm?.refresh()
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView(paywallSource: "insights_tab")
            }
        }
    }
}

// MARK: - Locked state for Free plan
private struct AnalyticsLockedView: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)

            Text("Insights is a Premium feature")
                .font(.title3.bold())
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)

            Text("Upgrade to Premium to see snore trends, daily charts, and alert correlations.")
                .font(.subheadline)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onUpgrade) {
                Text("Upgrade to Premium")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clearsFloatingTabBar()
    }
}

// MARK: - Scrollable page content
@MainActor
private struct AnalyticsContent: View {

    @Bindable var vm: AnalyticsViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var areSettingsChangesExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangePicker
                if !vm.dailyPoints.isEmpty { summaryRow }
                snoreTrendCard
                AlertCorrelationCard(points: vm.alertProfilePoints, xMax: vm.alertChartXMax)
                if !vm.settingsChanges.isEmpty {
                    SettingsChangeLegend(
                        changes: vm.settingsChanges,
                        isExpanded: $areSettingsChangesExpanded,
                        onDelete: { change in
                            vm.deleteSettingsChange(change)
                        }
                    )
                }
                if vm.settingsChanges.isEmpty { markerInfoNote }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            .padding(.bottom, horizontalSizeClass == .regular ? 16 : 24)
            .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .clearsFloatingTabBar()
    }

    // MARK: Range picker

    private var rangePicker: some View {
        Picker("Range", selection: $vm.selectedRange) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
        .onChange(of: vm.selectedRange) { _, _ in vm.refresh() }
    }

    // MARK: Summary stats row

    private var summaryRow: some View {
        HStack(spacing: 12) {
            statPill("Avg min/day", avgSnoreLabel, Theme.snoring)
            statPill("Sessions",   "\(vm.sessionCount)", Theme.accent)
            statPill("Days",       "\(vm.dailyPoints.count)", Theme.good)
        }
    }

    private var avgSnoreLabel: String {
        let m = vm.averageDailySnoreMinutes
        guard m > 0 else { return "—" }
        if m < 1 { return "<1m" }
        return "\(Int(m.rounded()))m"
    }

    private func statPill(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.monoDigit(size: 20, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    // MARK: Trend chart card wrapper

    private var snoreTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader
            if vm.dailyPoints.isEmpty {
                emptyChartState
            } else {
                SnoreDailyBarsChart(
                    dailyPoints: vm.dailyPoints,
                    settingsChanges: vm.settingsChanges,
                    cutoffDate: vm.cutoffDate,
                    snoreMinutesYMax: vm.snoreMinutesYMax,
                    eventCountYMax: vm.eventCountYMax,
                    selectedRange: vm.selectedRange
                )
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var cardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Snore duration")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Text("Daily totals · \(vm.selectedRange.rawValue.lowercased())")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
            }
            Spacer()
            if !vm.settingsChanges.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Theme.warning).frame(width: 8, height: 8)
                    Text("Settings changes")
                        .font(.caption2)
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                }
            }
        }
    }

    private var emptyChartState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)
            Text("No sessions in this period")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.labelSecondary)
            Text("Start a recording session to see your snore trends here.")
                .font(.caption)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Info note (shown when no markers exist yet)

    private var markerInfoNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.accent.opacity(0.7))
                .font(.subheadline)
                .padding(.top, 1)
            Text(
                "Settings change markers will appear on the chart once you save changes in " +
                "Settings. This lets you track which push notification or alarm settings " +
                "affected your snore duration and event count."
            )
            .font(.caption)
            .foregroundStyle(Theme.labelOnSurfaceSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Dual daily bar chart (snore events + snore duration)
private struct SnoreDailyBarsChart: View {

    let dailyPoints: [DailySnorePoint]
    let settingsChanges: [AlertSettingsChange]
    let cutoffDate: Date
    let snoreMinutesYMax: Double
    let eventCountYMax: Double
    let selectedRange: AnalyticsRange

    /// Fixed width for trailing Y-axis tick labels so both charts’ plot areas share the same horizontal inset.
    private enum Layout {
        static let trailingYLabelWidth: CGFloat = 42
        static let chartSubtitleHeight: CGFloat = 16
    }

    var body: some View {
        VStack(spacing: 12) {
            // Events chart
            VStack(alignment: .leading, spacing: 4) {
                Text("Snore events")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.snoring)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .frame(maxWidth: .infinity, minHeight: Layout.chartSubtitleHeight, alignment: .leading)
                Chart {
                    eventBars
                    changeRules(yMax: eventCountYMax)
                }
                .chartXScale(domain: cutoffDate...Date())
                .chartYScale(domain: 0...eventCountYMax)
                .chartXAxis { xAxisContent }
                .chartYAxis { intYAxisContent() }
                .frame(height: 110)
            }

            // Snore duration chart
            VStack(alignment: .leading, spacing: 4) {
                Text("Snore duration (min)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .frame(maxWidth: .infinity, minHeight: Layout.chartSubtitleHeight, alignment: .leading)
                Chart {
                    durationBars
                    changeRules(yMax: snoreMinutesYMax)
                }
                .chartXScale(domain: cutoffDate...Date())
                .chartYScale(domain: 0...snoreMinutesYMax)
                .chartXAxis { xAxisContent }
                .chartYAxis { minuteYAxisContent() }
                .frame(height: 110)
            }
        }
    }

    // MARK: Bar marks

    @ChartContentBuilder
    private var eventBars: some ChartContent {
        ForEach(dailyPoints) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Events", point.eventCount)
            )
            .foregroundStyle(Theme.snoring.opacity(0.85))
            .cornerRadius(4)
            .annotation(position: .top, spacing: 2) {
                if point.eventCount > 0 {
                    Text("\(point.eventCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
        }
    }

    @ChartContentBuilder
    private var durationBars: some ChartContent {
        ForEach(dailyPoints) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Snore min", point.snoreMinutes)
            )
            .foregroundStyle(Theme.accent.opacity(0.85))
            .cornerRadius(4)
            .annotation(position: .top, spacing: 2) {
                if point.snoreMinutes > 0 {
                    Text(minuteLabel(point.snoreMinutes))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
        }
    }

    @ChartContentBuilder
    private func changeRules(yMax: Double) -> some ChartContent {
        ForEach(Array(settingsChanges.enumerated()), id: \.offset) { index, change in
            // Snap to start-of-day so markers align with daily bars.
            RuleMark(
                x: .value(
                    "Settings changed",
                    Calendar.current.startOfDay(for: change.timestamp),
                    unit: .day
                )
            )
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(Theme.warning.opacity(0.80))
                .annotation(position: .top, alignment: .center, spacing: 6) {
                    markerBadge(number: index + 1)
                }
        }
    }

    // MARK: Axis helpers

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: xAxisMarkCount)) { _ in
            AxisGridLine().foregroundStyle(Theme.surfaceSecondary)
            AxisValueLabel(format: xAxisFormat)
                .foregroundStyle(Theme.labelSecondary)
                .font(.caption2)
        }
    }

    @AxisContentBuilder
    private func intYAxisContent() -> some AxisContent {
        AxisMarks(
            preset: .automatic,
            position: .trailing,
            values: .automatic(desiredCount: 4)
        ) { value in
            AxisGridLine().foregroundStyle(Theme.surfaceSecondary.opacity(0.6))
            AxisValueLabel {
                if let n = yAxisInt(from: value) {
                    Text("\(n)")
                        .font(Theme.monoDigit(size: 11))
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                        .frame(width: Layout.trailingYLabelWidth, alignment: .trailing)
                }
            }
        }
    }

    @AxisContentBuilder
    private func minuteYAxisContent() -> some AxisContent {
        AxisMarks(
            preset: .automatic,
            position: .trailing,
            values: .automatic(desiredCount: 4)
        ) { value in
            AxisGridLine().foregroundStyle(Theme.surfaceSecondary.opacity(0.6))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text("\(Int(v))m")
                        .font(Theme.monoDigit(size: 11))
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                        .frame(width: Layout.trailingYLabelWidth, alignment: .trailing)
                }
            }
        }
    }

    /// Axis mark values use `Double` for numeric domains; normalise so labels always render with stable width.
    private func yAxisInt(from value: Charts.AxisValue) -> Int? {
        if let v = value.as(Int.self) { return v }
        if let v = value.as(Double.self) { return Int(v.rounded()) }
        return nil
    }

    private var xAxisMarkCount: Int {
        switch selectedRange {
        case .week:        return 7
        case .month:       return 5
        case .threeMonths: return 3
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .week:        return .dateTime.weekday(.abbreviated)
        case .month:       return .dateTime.month(.abbreviated).day()
        case .threeMonths: return .dateTime.month(.abbreviated)
        }
    }

    private func minuteLabel(_ minutes: Double) -> String {
        if minutes < 1 { return "<1m" }
        return "\(Int(minutes.rounded()))m"
    }

    private func markerBadge(number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.warning)
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(Theme.background)
                    .overlay(Circle().strokeBorder(Theme.warning, lineWidth: 1.5))
            )
    }
}

// MARK: - Settings change legend card
private struct SettingsChangeLegend: View {

    let changes: [AlertSettingsChange]
    @Binding var isExpanded: Bool
    let onDelete: (AlertSettingsChange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    header
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Settings changes")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse settings changes" : "Expand settings changes")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Numbered markers on the chart correspond to rows below.")
                        .font(.caption)
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    VStack(spacing: 10) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                            changeRow(index: index, change: change)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        onDelete(change)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.warning).frame(width: 8, height: 8)
            Text("Settings changes")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)
        }
    }

    private func changeRow(index: Int, change: AlertSettingsChange) -> some View {
        HStack(alignment: .top, spacing: 12) {
            badge(number: index + 1).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(change.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                Text(change.summaryLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func badge(number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.warning)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(Theme.background)
                    .overlay(Circle().strokeBorder(Theme.warning, lineWidth: 1.5))
            )
    }
}

// MARK: - Alert configuration vs snore duration card
private struct AlertCorrelationCard: View {

    let points: [AlertProfilePoint]
    let xMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader
            if points.isEmpty {
                emptyState
            } else {
                AlertCorrelationChart(points: points, xMax: xMax)
                disclaimer
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Alert Type vs Snore duration")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)
            Text("Average per alert configuration · sessions in this period")
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)
            Text("No data yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.labelSecondary)
            Text("Complete a recording session to see how your alert settings correlate with snore duration.")
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var disclaimer: some View {
        Text("Shorter is better. Correlation only — not a causal measure.")
            .font(.caption2)
            .foregroundStyle(Theme.labelOnSurfaceSecondary)
            .padding(.top, 2)
    }
}

// MARK: - Horizontal bar chart (snore duration per alert profile)
private struct AlertCorrelationChart: View {

    let points: [AlertProfilePoint]
    let xMax: Double

    /// Colour gradient: green at 0, red at xMax.
    private func barColor(for minutes: Double) -> Color {
        let t = min(max(xMax > 0 ? minutes / xMax : 0, 0), 1)
        return Color(
            red:   0.25 + 0.55 * t,
            green: 0.75 - 0.45 * t,
            blue:  0.35 - 0.15 * t
        )
    }

    private func minuteLabel(_ minutes: Double) -> String {
        if minutes < 1 { return "<1m" }
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Avg snore (min)", point.avgSnoreMinutes),
                y: .value("Profile", point.label)
            )
            .foregroundStyle(barColor(for: point.avgSnoreMinutes))
            .cornerRadius(6)
            .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(minuteLabel(point.avgSnoreMinutes))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.labelPrimary)
                    Text("n=\(point.sessionCount)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(point.isLowConfidence ? Theme.warning : Theme.labelOnSurfaceSecondary)
                }
            }
        }
        .chartXScale(domain: 0...xMax)
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisGridLine().foregroundStyle(Theme.surfaceSecondary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))m")
                            .font(.caption2)
                            .foregroundStyle(Theme.labelOnSurfaceSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Theme.labelSecondary)
            }
        }
        .frame(height: max(56, CGFloat(points.count) * 52))
    }

    private var xTicks: [Double] {
        stride(from: 0, through: xMax, by: max(1, xMax / 4).rounded()).map { $0 }
    }
}
