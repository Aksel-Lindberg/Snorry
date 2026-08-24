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

    private var canAccessInsights: Bool {
        InsightsTrialTracker.canAccessInsights(hasPremium: hasPremiumAccess, context: context)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                if canAccessInsights {
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
                InsightsTrialTracker.updateMaxCompletedNights(from: context)
                guard canAccessInsights else {
                    AppAnalytics.logPaywallViewed(source: "insights_tab")
                    showSubscription = true
                    return
                }
                if vm == nil { vm = AnalyticsViewModel(context: context) }
                vm?.refresh()
            }
            .onChange(of: hasPremiumAccess) { _, _ in
                InsightsTrialTracker.updateMaxCompletedNights(from: context)
                guard canAccessInsights else {
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

            Text(
                "Insights is free for your first \(InsightsTrialTracker.freeNightLimit) recorded nights. " +
                "Subscribe to keep snore trends, daily charts, habit correlations, and alert comparisons."
            )
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
    @State private var areEventsExpanded = false
    @State private var selectedChartDay: Date?
    @State private var highlightedChartDay: Date?
    @State private var sessionDetailRoute: SessionDetailRoute?
    @State private var multiSessionPicker: ChartDayPicker?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangePicker
                if vm.hasSessionDataInPeriod {
                    metricCardsRow
                    InsightBanner(message: vm.insightMessage)
                }
                snoreTrendCard
                HabitCorrelationCard(
                    points: vm.habitCorrelationPoints,
                    xMax: vm.habitChartXMax,
                    range: vm.selectedRange,
                    onSelectMonth: {
                        vm.setRange(.month)
                    }
                )
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
            .padding(.bottom, horizontalSizeClass == .regular ? 16 : 24)
            .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .clearsFloatingTabBar()
        .navigationDestination(item: $sessionDetailRoute) { route in
            if let session = vm.session(withID: route.sessionID) {
                SessionDetailView(session: session)
            }
        }
        .sheet(item: $multiSessionPicker) { picker in
            InsightsDaySessionsSheet(dayStart: picker.dayStart, vm: vm) { session in
                multiSessionPicker = nil
                sessionDetailRoute = SessionDetailRoute(sessionID: session.id)
            }
        }
        .onChange(of: selectedChartDay) { _, newValue in
            handleChartDayHighlight(newValue)
        }
        .onChange(of: vm.selectedRange) { _, _ in
            highlightedChartDay = nil
        }
        .onChange(of: vm.periodOffset) { _, _ in
            highlightedChartDay = nil
        }
    }

    /// Shows a callout for the tapped night; navigation happens when the user opens the callout.
    private func handleChartDayHighlight(_ date: Date?) {
        guard let date else { return }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let hadSession = vm.dailyPoints.contains {
            calendar.isDate($0.date, inSameDayAs: dayStart) && $0.hadSession
        }
        highlightedChartDay = hadSession ? dayStart : nil
        selectedChartDay = nil
    }

    private func openHighlightedChartDay() {
        guard let dayStart = highlightedChartDay else { return }
        let sessions = vm.sessions(on: dayStart)
        guard !sessions.isEmpty else {
            highlightedChartDay = nil
            return
        }
        if sessions.count == 1, let session = sessions.first {
            sessionDetailRoute = SessionDetailRoute(sessionID: session.id)
        } else {
            multiSessionPicker = ChartDayPicker(dayStart: dayStart)
        }
        highlightedChartDay = nil
    }

    private func dailyPoint(for dayStart: Date) -> DailySnorePoint? {
        let calendar = Calendar.current
        return vm.dailyPoints.first { calendar.isDate($0.date, inSameDayAs: dayStart) }
    }

    // MARK: Range picker

    private var rangePicker: some View {
        VStack(spacing: 12) {
            Picker("Range", selection: Binding(
                get: { vm.selectedRange },
                set: { vm.setRange($0) }
            )) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if vm.selectedRange.allowsPaging {
                periodPager
            }
        }
        .padding(.top, 4)
    }

    private var periodPager: some View {
        HStack(spacing: 8) {
            Button {
                vm.goToPreviousPeriod()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!vm.canGoBack)
            .opacity(vm.canGoBack ? 1 : 0.35)
            .accessibilityLabel("Previous \(vm.selectedRange.pagingUnitName)")

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(vm.periodTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)
                    .multilineTextAlignment(.center)
                if let subtitle = vm.periodSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                vm.goToNextPeriod()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!vm.canGoForward)
            .opacity(vm.canGoForward ? 1 : 0.35)
            .accessibilityLabel("Next \(vm.selectedRange.pagingUnitName)")
        }
        .foregroundStyle(Theme.accent)
        .buttonStyle(.plain)
    }

    // MARK: Summary metric cards

    private var metricCardsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            metricCard(
                icon: "clock.fill",
                title: "Avg duration",
                value: avgSnoreLabel,
                delta: avgDurationDeltaLabel,
                deltaIsPositive: vm.averageDurationPercentChange.map { $0 < 0 } ?? false,
                accent: Theme.snoring
            )
            metricCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Sessions",
                value: "\(vm.sessionCount)",
                delta: sessionDeltaLabel,
                deltaIsPositive: true,
                accent: Theme.accent
            )
            metricCard(
                icon: "moon.stars.fill",
                title: goodNightsTitle,
                value: "\(vm.currentPeriod.nightsUnderThreshold)",
                delta: goodNightsDeltaLabel,
                deltaIsPositive: vm.goodNightsDelta >= 0,
                accent: Theme.good
            )
        }
    }

    private var goodNightsTitle: String {
        let threshold = Int(InsightsConfiguration.goodNightSnoreMinutesThreshold)
        return "Nights <\(threshold)m"
    }

    private var avgSnoreLabel: String {
        guard vm.hasSessionDataInPeriod else { return "—" }
        return minuteLabel(vm.averageDailySnoreMinutes)
    }

    private var priorLabel: String { vm.selectedRange.previousPeriodLabel }

    private var insufficientPriorDataLabel: String {
        vm.selectedRange == .threeMonths ? "— not enough prior data" : "— vs \(priorLabel)"
    }

    private var avgDurationDeltaLabel: String {
        guard vm.hasComparablePreviousPeriod else { return insufficientPriorDataLabel }
        guard let change = vm.averageDurationPercentChange else {
            return "new vs \(priorLabel)"
        }
        let rounded = Int(abs(change).rounded())
        let arrow = change < 0 ? "↓" : "↑"
        return "\(arrow) \(rounded)% vs \(priorLabel)"
    }

    private var sessionDeltaLabel: String {
        guard vm.hasComparablePreviousPeriod else { return insufficientPriorDataLabel }
        let delta = vm.sessionCountDelta
        if delta == 0 { return "same vs \(priorLabel)" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(delta) vs \(priorLabel)"
    }

    private var goodNightsDeltaLabel: String {
        guard vm.hasComparablePreviousPeriod else { return insufficientPriorDataLabel }
        let delta = vm.goodNightsDelta
        if delta == 0 { return "same vs \(priorLabel)" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(delta) vs \(priorLabel)"
    }

    private func metricCard(
        icon: String,
        title: String,
        value: String,
        delta: String,
        deltaIsPositive: Bool,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            Text(value)
                .font(Theme.monoDigit(size: 22, weight: .bold))
                .foregroundStyle(Theme.labelPrimary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .textCase(.uppercase)
                .tracking(0.4)

            Text(delta)
                .font(.caption2)
                .foregroundStyle(deltaIsPositive ? Theme.good : Theme.labelOnSurfaceSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    // MARK: Trend chart card wrapper

    private var snoreTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader
            if !vm.hasSessionDataInPeriod {
                emptyChartState
            } else {
                SnoreDurationHeroChart(
                    dailyPoints: vm.chartDailyPoints,
                    trendLinePoints: vm.trendLinePoints,
                    exerciseLoggedDayStarts: vm.exerciseLoggedDayStarts,
                    cutoffDate: vm.cutoffDate,
                    chartEndDate: vm.chartEndDate,
                    snoreMinutesYMax: vm.snoreMinutesYMax,
                    selectedRange: vm.selectedRange,
                    highlightedDay: highlightedChartDay,
                    selectedDay: $selectedChartDay
                )

                if let dayStart = highlightedChartDay, let point = dailyPoint(for: dayStart) {
                    ChartNightCallout(
                        point: point,
                        hadExercise: vm.exerciseLoggedDayStarts.contains(dayStart),
                        onOpen: openHighlightedChartDay
                    )
                }

                if let hint = sessionPresenceHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Theme.labelTertiary)
                }

                CollapsibleSnoreEventsChart(
                    dailyPoints: vm.dailyPoints,
                    cutoffDate: vm.cutoffDate,
                    chartEndDate: vm.chartEndDate,
                    eventCountYMax: vm.eventCountYMax,
                    selectedRange: vm.selectedRange,
                    isExpanded: $areEventsExpanded
                )
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily snore duration")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Text(chartSubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
            }

            chartLegendRow

            if let best = vm.bestSnoreDay, let worst = vm.worstSnoreDay,
               vm.currentPeriod.sessionDays.count >= 2,
               best.date != worst.date || best.snoreMinutes != worst.snoreMinutes {
                Text("Best: \(daySnoreLabel(best)) · Worst: \(daySnoreLabel(worst))")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
            }
        }
    }

    private var chartSubtitle: String {
        let recorded = vm.currentPeriod.sessionDays.count
        let hasGap = vm.dailyPoints.contains { !$0.hadSession }
        if hasGap {
            let nightsLabel = recorded == 1 ? "night" : "nights"
            return "Last \(vm.selectedRange.days) days · \(recorded) \(nightsLabel) recorded"
        }
        return "Minutes per night · \(vm.selectedRange.rawValue.lowercased())"
    }

    private var chartLegendRow: some View {
        HStack(spacing: 12) {
            if vm.trendLinePoints != nil {
                HStack(spacing: 4) {
                    trendLegendDash
                    Text("Trend")
                        .font(.caption2)
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                }
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: 18, height: 8)
                Text("No airway exercises")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.good.opacity(0.65))
                    .frame(width: 18, height: 8)
                Text("Exercises")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
            }
        }
    }

    private var trendLegendDash: some View {
        RoundedRectangle(cornerRadius: 1)
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            .foregroundStyle(Color.purple.opacity(0.85))
            .frame(width: 18, height: 2)
    }

    private func daySnoreLabel(_ point: DailySnorePoint) -> String {
        let day = point.date.formatted(.dateTime.weekday(.abbreviated))
        return "\(day) \(minuteLabel(point.snoreMinutes))"
    }

    /// Explains 0-snore recorded nights vs days with no session on the chart.
    private var sessionPresenceHint: String? {
        guard vm.hasSessionDataInPeriod else { return nil }
        let hasQuiet = vm.dailyPoints.contains { $0.hadSession && $0.snoreMinutes <= 0 }
        let hasGap = vm.dailyPoints.contains { !$0.hadSession }
        let hasTrend = vm.trendLinePoints != nil
        let isLongRange = vm.selectedRange != .week

        switch (hasQuiet, hasGap) {
        case (true, true):
            if isLongRange {
                if hasTrend {
                    return "0m is a recorded quiet night. Trend uses recorded nights only."
                }
                return "0m is a recorded quiet night."
            }
            if hasTrend {
                return "0m is a recorded quiet night. Empty days were not recorded. Trend uses recorded nights only."
            }
            return "0m is a recorded quiet night. Empty days were not recorded."
        case (true, false):
            return "0m is a recorded quiet night."
        case (false, true):
            if isLongRange {
                return hasTrend ? "Trend uses recorded nights only." : nil
            }
            return hasTrend
                ? "Empty days were not recorded. Trend uses recorded nights only."
                : "Empty days were not recorded."
        case (false, false):
            return nil
        }
    }

    private func minuteLabel(_ minutes: Double) -> String {
        Self.minuteLabel(minutes)
    }

    static func minuteLabel(_ minutes: Double) -> String {
        guard minutes > 0 else { return "0m" }
        if minutes < 1 { return "<1m" }
        return "\(Int(minutes.rounded()))m"
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
}

// MARK: - Navigation route for session detail from chart
private struct SessionDetailRoute: Identifiable, Hashable {
    let sessionID: UUID
    var id: UUID { sessionID }
}

private struct ChartDayPicker: Identifiable {
    let dayStart: Date
    var id: TimeInterval { dayStart.timeIntervalSinceReferenceDate }
}

/// Shared Insights x-axis: recorded days stay full-contrast, unrecorded days are dimmed.
@AxisContentBuilder
private func snoreChartXAxis(
    points: [DailySnorePoint],
    markCount: Int,
    format: Date.FormatStyle,
    explicitDates: [Date]? = nil
) -> some AxisContent {
    if let explicitDates, !explicitDates.isEmpty {
        AxisMarks(values: explicitDates) { value in
            AxisGridLine().foregroundStyle(Theme.surfaceSecondary)
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: format)
                        .font(.caption2)
                        .foregroundStyle(snoreChartXAxisLabelColor(for: date, in: points))
                }
            }
        }
    } else {
        AxisMarks(values: .automatic(desiredCount: markCount)) { value in
            AxisGridLine().foregroundStyle(Theme.surfaceSecondary)
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date, format: format)
                        .font(.caption2)
                        .foregroundStyle(snoreChartXAxisLabelColor(for: date, in: points))
                }
            }
        }
    }
}

private func snoreChartXAxisLabelColor(for date: Date, in points: [DailySnorePoint]) -> Color {
    let recorded = points.contains {
        Calendar.current.isDate($0.date, inSameDayAs: date) && $0.hadSession
    }
    return recorded ? Theme.labelSecondary : Theme.labelTertiary
}

// MARK: - Insight narrative banner
private struct InsightBanner: View {

    let message: InsightMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Theme.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var iconName: String {
        switch message.tone {
        case .trendingDown: return "arrow.down.circle.fill"
        case .trendingUp: return "arrow.up.circle.fill"
        case .flat: return "minus.circle.fill"
        case .insufficientData: return "chart.line.uptrend.xyaxis.circle"
        }
    }

    private var iconColor: Color {
        switch message.tone {
        case .trendingDown: return Theme.good
        case .trendingUp: return Theme.snoring
        case .flat: return Theme.accent
        case .insufficientData: return Theme.labelTertiary
        }
    }
}

// MARK: - Multiple sessions on one chart day
private struct InsightsDaySessionsSheet: View {

    let dayStart: Date
    let vm: AnalyticsViewModel
    let onSelect: (SnoreSession) -> Void

    @Environment(\.dismiss) private var dismiss

    private var sessions: [SnoreSession] { vm.sessions(on: dayStart) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                List {
                    let maxSnore = sessions.map(\.totalSnoreDuration).max() ?? 0
                    ForEach(sessions, id: \.id) { session in
                        Button {
                            onSelect(session)
                            dismiss()
                        } label: {
                            SessionRowView(session: session, maxSnoreDuration: maxSnore)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle(dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Selected-night callout under the duration chart
private struct ChartNightCallout: View {

    let point: DailySnorePoint
    let hadExercise: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(primaryCalloutText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.labelPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }

                if !eventTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(eventTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tagColor(for: tag))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tagColor(for: tag).opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calloutAccessibilityLabel)
        .accessibilityHint("Opens that night's sleep session")
    }

    private var primaryCalloutText: String {
        let date = point.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let events = point.eventCount == 1 ? "1 event" : "\(point.eventCount) events"
        return "\(date) · \(AnalyticsContent.minuteLabel(point.snoreMinutes)) · \(events)"
    }

    private var eventTags: [String] {
        hadExercise ? ["Exercises"] : []
    }

    private func tagColor(for tag: String) -> Color {
        Theme.good
    }

    private var calloutAccessibilityLabel: String {
        let date = point.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let events = point.eventCount == 1 ? "1 snore event" : "\(point.eventCount) snore events"
        var label = "\(date), \(AnalyticsContent.minuteLabel(point.snoreMinutes)), \(events)"
        if hadExercise { label += ", airway exercises logged" }
        return label
    }
}

// MARK: - Hero duration chart (bars, trend, markers, selection)
private struct SnoreDurationHeroChart: View {

    let dailyPoints: [DailySnorePoint]
    let trendLinePoints: [TrendLinePoint]?
    let exerciseLoggedDayStarts: Set<Date>
    let cutoffDate: Date
    let chartEndDate: Date
    let snoreMinutesYMax: Double
    let selectedRange: AnalyticsRange
    let highlightedDay: Date?
    @Binding var selectedDay: Date?

    private enum Layout {
        static let trailingYLabelWidth: CGFloat = 42
    }

    var body: some View {
        Chart {
            durationBars
            if let trendLinePoints {
                ForEach(trendLinePoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Trend", point.predictedMinutes)
                    )
                    .foregroundStyle(Color.purple.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .interpolationMethod(.linear)
                }
            }
        }
        .chartXScale(domain: cutoffDate...chartEndDate)
        .chartYScale(domain: 0...snoreMinutesYMax)
        .chartXAxis { xAxisContent }
        .chartYAxis { minuteYAxisContent() }
        .chartXSelection(value: $selectedDay)
        .frame(height: chartHeight)
        .accessibilityLabel("Daily snore duration chart")
        .accessibilityHint("Select a day to see that night's details")
    }

    private var chartHeight: CGFloat {
        switch selectedRange {
        case .week:        return 172
        case .month:       return 200
        case .threeMonths: return 228
        }
    }

    @ChartContentBuilder
    private var durationBars: some ChartContent {
        ForEach(dailyPoints.filter(\.hadSession)) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Snore min", point.snoreMinutes)
            )
            .foregroundStyle(barFill(for: point))
            .cornerRadius(4)
            .accessibilityLabel(durationAccessibilityLabel(for: point))
            .annotation(position: .top, spacing: 2) {
                durationAnnotation(for: point)
            }
        }
    }

    private func barFill(for point: DailySnorePoint) -> Color {
        let highlighted = isDayHighlighted(point)
        if hasExercise(on: point.date) {
            return Theme.good.opacity(highlighted ? 0.85 : 0.65)
        }
        return Theme.accent.opacity(highlighted ? 1 : 0.85)
    }

    private func isDayHighlighted(_ point: DailySnorePoint) -> Bool {
        guard let highlightedDay else { return false }
        return Calendar.current.isDate(point.date, inSameDayAs: highlightedDay)
    }

    @ViewBuilder
    private func durationAnnotation(for point: DailySnorePoint) -> some View {
        if point.snoreMinutes > 0 {
            if selectedRange == .week {
                Text(minuteLabel(point.snoreMinutes))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.labelSecondary)
            }
        } else if point.hadSession {
            let barTint = hasExercise(on: point.date) ? Theme.good.opacity(0.85) : Theme.accent.opacity(0.85)
            if selectedRange == .week {
                VStack(spacing: 3) {
                    Text("0m")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.labelSecondary)
                    Capsule()
                        .fill(barTint)
                        .frame(width: 14, height: 4)
                }
            } else if selectedRange == .month {
                VStack(spacing: 3) {
                    Text("0")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.labelSecondary)
                    Capsule()
                        .fill(barTint)
                        .frame(width: 14, height: 4)
                }
            }
        }
    }

    private func durationAccessibilityLabel(for point: DailySnorePoint) -> String {
        let day = point.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        var label: String
        if point.snoreMinutes <= 0 {
            label = "\(day), quiet night, 0 minutes"
        } else {
            label = "\(day), \(minuteLabel(point.snoreMinutes))"
        }
        if hasExercise(on: point.date) {
            label += ", airway exercises logged"
        }
        return label
    }

    private func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func hasExercise(on date: Date) -> Bool {
        exerciseLoggedDayStarts.contains(dayStart(date))
    }

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        let explicitWeekDates = selectedRange == .week ? dailyPoints.map(\.date) : nil
        snoreChartXAxis(
            points: dailyPoints,
            markCount: xAxisMarkCount,
            format: xAxisFormat,
            explicitDates: explicitWeekDates
        )
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
        AnalyticsContent.minuteLabel(minutes)
    }
}

// MARK: - Collapsible snore events chart
private struct CollapsibleSnoreEventsChart: View {

    let dailyPoints: [DailySnorePoint]
    let cutoffDate: Date
    let chartEndDate: Date
    let eventCountYMax: Double
    let selectedRange: AnalyticsRange
    @Binding var isExpanded: Bool

    private enum Layout {
        static let trailingYLabelWidth: CGFloat = 42
        static let chartSubtitleHeight: CGFloat = 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Snore events")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.snoring)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Chart {
                    ForEach(dailyPoints.filter(\.hadSession)) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Events", point.eventCount)
                        )
                        .foregroundStyle(Theme.snoring.opacity(0.85))
                        .cornerRadius(4)
                        .accessibilityLabel(eventsAccessibilityLabel(for: point))
                        .annotation(position: .top, spacing: 2) {
                            eventsAnnotation(for: point)
                        }
                    }
                }
                .chartXScale(domain: cutoffDate...chartEndDate)
                .chartYScale(domain: 0...eventCountYMax)
                .chartXAxis { xAxisContent }
                .chartYAxis { intYAxisContent() }
                .frame(height: 110)
            }
        }
    }

    @ViewBuilder
    private func eventsAnnotation(for point: DailySnorePoint) -> some View {
        if point.eventCount > 0 {
            if selectedRange == .week {
                Text("\(point.eventCount)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.labelSecondary)
            }
        } else {
            VStack(spacing: 3) {
                Text("0")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.labelSecondary)
                Capsule()
                    .fill(Theme.snoring.opacity(0.85))
                    .frame(width: 14, height: 4)
            }
        }
    }

    private func eventsAccessibilityLabel(for point: DailySnorePoint) -> String {
        let day = point.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if point.eventCount == 0 {
            return "\(day), quiet night, 0 snore events"
        }
        let noun = point.eventCount == 1 ? "snore event" : "snore events"
        return "\(day), \(point.eventCount) \(noun)"
    }

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        snoreChartXAxis(points: dailyPoints, markCount: xAxisMarkCount, format: xAxisFormat)
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
}

// MARK: - Shared minute-axis helpers for correlation bar charts
private enum CorrelationMinuteChartStyle {

    static func minuteLabel(_ minutes: Double) -> String {
        if minutes < 1 { return "<1m" }
        let total = Int(minutes.rounded())
        let hours = total / 60
        let remainder = total % 60
        if hours > 0 {
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(remainder)m"
    }

    static func xTicks(upTo xMax: Double) -> [Double] {
        stride(from: 0, through: xMax, by: max(1, xMax / 4).rounded()).map { $0 }
    }
}

// MARK: - Habit vs snore duration section
private struct HabitCorrelationCard: View {

    let points: [HabitCorrelationPoint]
    let xMax: Double
    let range: AnalyticsRange
    let onSelectMonth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader
            if !range.showsHabitCorrelation {
                rangeLockedState
            } else if points.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(points) { point in
                        HabitCorrelationHabitCard(point: point, xMax: xMax)
                    }
                }
                footnotes
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Habits vs Snore duration")
                .font(.headline)
                .foregroundStyle(Theme.labelPrimary)
            Text(headerSubtitle)
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
        }
    }

    private var headerSubtitle: String {
        if range.showsHabitCorrelation {
            return "Average snore minutes logged vs not logged"
        }
        return "Shown for Month and 3 Months"
    }

    private var rangeLockedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)
            Text("Need a longer range")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.labelSecondary)
            Text("A week is too short to compare habits with snore duration. Switch to Month or 3 Months to see correlations.")
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: onSelectMonth) {
                Text("View Month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.accentGradient, in: Capsule())
            }
            .padding(.top, 4)
            .accessibilityHint("Switches Insights to the Month range")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 38, weight: .thin))
                .foregroundStyle(Theme.labelTertiary)
            Text("No habit logs yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.labelSecondary)
            Text("Log habits on the Habits tab to see how they relate to your snore duration over time.")
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("May add snoring / May reduce snoring is typical, not a diagnosis. Bars are your nights.")
            Text("Shorter is better. Correlation only — not a causal measure.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.labelOnSurfaceSecondary)
        .padding(.top, 2)
    }
}

// MARK: - One logged habit comparison
private struct HabitCorrelationHabitCard: View {

    let point: HabitCorrelationPoint
    let xMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: point.systemImage)
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(point.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.labelPrimary)

                    if let chipTitle = point.expectedEffect.chipTitle {
                        Text(chipTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(expectedEffectColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(expectedEffectColor.opacity(0.14), in: Capsule())
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headerAccessibilityLabel)

            HabitCorrelationChart(point: point, xMax: xMax)
            deltaBadge

            if point.isLowConfidence {
                Text("Early signal · log a few more nights")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(12)
        .background(Theme.surfaceSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private var deltaBadge: some View {
        let delta = point.deltaMinutes
        let color: Color = {
            if abs(delta) < 1 { return Theme.labelSecondary }
            return delta > 0 ? Theme.snoring : Theme.good
        }()

        return Text(point.deltaSummary)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.14), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(point.deltaSummary)
    }

    private var expectedEffectColor: Color {
        switch point.expectedEffect {
        case .mayAddSnoring: return Theme.snoring
        case .mayHelp:       return Theme.good
        case .howYouFelt:    return Theme.warning
        case .unknown:       return Theme.labelSecondary
        }
    }

    private var headerAccessibilityLabel: String {
        if let chipTitle = point.expectedEffect.chipTitle {
            return "\(point.title), \(chipTitle)"
        }
        return point.title
    }
}

// MARK: - Two-bar comparison for one habit
private struct HabitCorrelationChart: View {

    let point: HabitCorrelationPoint
    let xMax: Double

    private var bars: [HabitBarDatum] {
        var result = [
            HabitBarDatum(
                id: "with",
                label: "Logged",
                minutes: point.avgWithHabitMinutes,
                nights: point.nightsWithHabit,
                isLowConfidence: point.isLowConfidenceWith,
                color: Theme.accent
            ),
            HabitBarDatum(
                id: "without",
                label: "Not logged",
                minutes: point.avgWithoutHabitMinutes,
                nights: point.nightsWithoutHabit,
                isLowConfidence: point.isLowConfidenceWithout,
                color: Theme.waveformBar
            )
        ]

        if let signedDeltaLabel = point.signedDeltaLabel {
            let delta = point.deltaMinutes
            result.append(
                HabitBarDatum(
                    id: "delta",
                    label: "Difference",
                    minutes: abs(delta),
                    nights: 0,
                    isLowConfidence: false,
                    color: delta > 0 ? Theme.snoring : Theme.good,
                    customAnnotation: signedDeltaLabel
                )
            )
        }

        return result
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Minutes", bar.minutes),
                y: .value("Group", bar.label)
            )
            .foregroundStyle(bar.color.opacity(point.isLowConfidence ? 0.55 : 0.92))
            .cornerRadius(6)
            .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                barAnnotation(for: bar)
            }
        }
        .chartXScale(domain: 0...xMax)
        .chartXAxis {
            AxisMarks(values: CorrelationMinuteChartStyle.xTicks(upTo: xMax)) { value in
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
        .frame(height: max(56, CGFloat(bars.count) * 52))
        .opacity(point.isLowConfidence ? 0.92 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habitChartAccessibilityLabel)
    }

    @ViewBuilder
    private func barAnnotation(for bar: HabitBarDatum) -> some View {
        if let customAnnotation = bar.customAnnotation {
            Text(customAnnotation)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(bar.color)
        } else {
            HStack(spacing: 4) {
                Text(CorrelationMinuteChartStyle.minuteLabel(bar.minutes))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.labelPrimary)
                Text("n=\(bar.nights)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(bar.isLowConfidence ? Theme.warning : Theme.labelOnSurfaceSecondary)
            }
        }
    }

    private var habitChartAccessibilityLabel: String {
        var label =
            "\(point.title). Logged \(HabitCorrelationPoint.minuteLabel(point.avgWithHabitMinutes)) over \(point.nightsWithHabit) nights. Not logged \(HabitCorrelationPoint.minuteLabel(point.avgWithoutHabitMinutes)) over \(point.nightsWithoutHabit) nights."
        if let signedDeltaLabel = point.signedDeltaLabel {
            label += " Difference \(signedDeltaLabel)."
        }
        return label
    }
}

private struct HabitBarDatum: Identifiable {
    let id: String
    let label: String
    let minutes: Double
    let nights: Int
    let isLowConfidence: Bool
    let color: Color
    var customAnnotation: String?
}
