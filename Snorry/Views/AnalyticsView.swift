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
    @State private var areSettingsChangesExpanded = true
    @State private var areEventsExpanded = false
    @State private var selectedChartDay: Date?
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
                AlertCorrelationCard(points: vm.alertProfilePoints, xMax: vm.alertChartXMax)
                HabitCorrelationCard(points: vm.habitCorrelationPoints)
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
            handleChartDaySelection(newValue)
        }
    }

    private func handleChartDaySelection(_ date: Date?) {
        guard let date else { return }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let sessions = vm.sessions(on: dayStart)
        guard !sessions.isEmpty else {
            selectedChartDay = nil
            return
        }
        if sessions.count == 1, let session = sessions.first {
            sessionDetailRoute = SessionDetailRoute(sessionID: session.id)
        } else {
            multiSessionPicker = ChartDayPicker(dayStart: dayStart)
        }
        selectedChartDay = nil
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
        let m = vm.averageDailySnoreMinutes
        guard m > 0 else { return "—" }
        if m < 1 { return "<1m" }
        return "\(Int(m.rounded()))m"
    }

    private var priorLabel: String { vm.selectedRange.previousPeriodLabel }

    private var avgDurationDeltaLabel: String {
        guard let change = vm.averageDurationPercentChange else {
            return vm.previousPeriod.sessionCount == 0 ? "— vs \(priorLabel)" : "new vs \(priorLabel)"
        }
        let rounded = Int(abs(change).rounded())
        let arrow = change < 0 ? "↓" : "↑"
        return "\(arrow) \(rounded)% vs \(priorLabel)"
    }

    private var sessionDeltaLabel: String {
        let delta = vm.sessionCountDelta
        if delta == 0 { return "same vs \(priorLabel)" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(delta) vs \(priorLabel)"
    }

    private var goodNightsDeltaLabel: String {
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
                    dailyPoints: vm.dailyPoints,
                    settingsChanges: vm.settingsChanges,
                    trendLinePoints: vm.trendLinePoints,
                    exerciseLoggedDayStarts: vm.exerciseLoggedDayStarts,
                    cutoffDate: vm.cutoffDate,
                    snoreMinutesYMax: vm.snoreMinutesYMax,
                    selectedRange: vm.selectedRange,
                    selectedDay: $selectedChartDay
                )

                CollapsibleSnoreEventsChart(
                    dailyPoints: vm.dailyPoints,
                    cutoffDate: vm.cutoffDate,
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily snore duration")
                        .font(.headline)
                        .foregroundStyle(Theme.labelPrimary)
                    Text("Minutes per night · \(vm.selectedRange.rawValue.lowercased())")
                        .font(.caption)
                        .foregroundStyle(Theme.labelOnSurfaceSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    if vm.trendLinePoints != nil {
                        HStack(spacing: 4) {
                            trendLegendDash
                            Text("Trend")
                                .font(.caption2)
                                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                        }
                    }
                    if showsExerciseLegend {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Theme.good)
                                .frame(width: 8, height: 8)
                            Text("Exercises completed")
                                .font(.caption2)
                                .foregroundStyle(Theme.labelOnSurfaceSecondary)
                        }
                    }
                }
            }

            if let best = vm.bestSnoreDay, let worst = vm.worstSnoreDay,
               vm.currentPeriod.sessionDays.count >= 2,
               best.date != worst.date || best.snoreMinutes != worst.snoreMinutes {
                Text("Best: \(daySnoreLabel(best)) · Worst: \(daySnoreLabel(worst))")
                    .font(.caption)
                    .foregroundStyle(Theme.labelOnSurfaceSecondary)
            }

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

    private var showsExerciseLegend: Bool {
        vm.dailyPoints.contains { vm.exerciseLoggedDayStarts.contains($0.date) }
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

    private func minuteLabel(_ minutes: Double) -> String {
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

// MARK: - Navigation route for session detail from chart
private struct SessionDetailRoute: Identifiable, Hashable {
    let sessionID: UUID
    var id: UUID { sessionID }
}

private struct ChartDayPicker: Identifiable {
    let dayStart: Date
    var id: TimeInterval { dayStart.timeIntervalSinceReferenceDate }
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

// MARK: - Hero duration chart (bars, trend, markers, selection)
private struct SnoreDurationHeroChart: View {

    let dailyPoints: [DailySnorePoint]
    let settingsChanges: [AlertSettingsChange]
    let trendLinePoints: [TrendLinePoint]?
    let exerciseLoggedDayStarts: Set<Date>
    let cutoffDate: Date
    let snoreMinutesYMax: Double
    let selectedRange: AnalyticsRange
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
            exerciseMarkers
            changeRules(yMax: snoreMinutesYMax)
        }
        .chartXScale(domain: cutoffDate...Date())
        .chartYScale(domain: 0...snoreMinutesYMax)
        .chartXAxis { xAxisContent }
        .chartYAxis { minuteYAxisContent() }
        .chartXSelection(value: $selectedDay)
        .frame(height: 172)
        .accessibilityLabel("Daily snore duration chart")
        .accessibilityHint("Select a day to open that night's sleep session")
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
    private var exerciseMarkers: some ChartContent {
        ForEach(exerciseDaysInRange, id: \.self) { day in
            PointMark(
                x: .value("Date", day, unit: .day),
                y: .value("Exercise", 0)
            )
            .symbolSize(28)
            .foregroundStyle(Theme.good.opacity(0.9))
            .annotation(position: .bottom, spacing: 2) {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.good)
            }
        }
    }

    private var exerciseDaysInRange: [Date] {
        dailyPoints
            .map(\.date)
            .filter { exerciseLoggedDayStarts.contains($0) }
    }

    @ChartContentBuilder
    private func changeRules(yMax: Double) -> some ChartContent {
        ForEach(Array(settingsChanges.enumerated()), id: \.offset) { index, change in
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

// MARK: - Collapsible snore events chart
private struct CollapsibleSnoreEventsChart: View {

    let dailyPoints: [DailySnorePoint]
    let cutoffDate: Date
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
                .chartXScale(domain: cutoffDate...Date())
                .chartYScale(domain: 0...eventCountYMax)
                .chartXAxis { xAxisContent }
                .chartYAxis { intYAxisContent() }
                .frame(height: 110)
            }
        }
    }

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

// MARK: - Legacy dual chart removed; settings legend unchanged below

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

// MARK: - Habit vs snore duration card
private struct HabitCorrelationCard: View {

    let points: [HabitCorrelationPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader
            if points.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(points) { point in
                        HabitCorrelationRow(point: point)
                    }
                }
                disclaimer
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
            Text("Average snore minutes with vs without each habit · nights in this period")
                .font(.caption)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
        }
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

    private var disclaimer: some View {
        Text("Shorter is better. Correlation only — not a causal measure.")
            .font(.caption2)
            .foregroundStyle(Theme.labelOnSurfaceSecondary)
            .padding(.top, 2)
    }
}

// MARK: - One habit correlation row
private struct HabitCorrelationRow: View {

    let point: HabitCorrelationPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(point.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.labelPrimary)

            HStack(spacing: 12) {
                metricColumn(
                    title: "With habit",
                    minutes: point.avgWithHabitMinutes,
                    nights: point.nightsWithHabit,
                    isLowConfidence: point.isLowConfidenceWith
                )
                metricColumn(
                    title: "Without",
                    minutes: point.avgWithoutHabitMinutes,
                    nights: point.nightsWithoutHabit,
                    isLowConfidence: point.isLowConfidenceWithout
                )
                Spacer(minLength: 0)
                deltaBadge
            }
        }
        .padding(12)
        .background(Theme.surfaceSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricColumn(
        title: String,
        minutes: Double,
        nights: Int,
        isLowConfidence: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.labelOnSurfaceSecondary)
            Text(minuteLabel(minutes))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.labelPrimary)
            Text("n=\(nights)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(isLowConfidence ? Theme.warning : Theme.labelOnSurfaceSecondary)
        }
    }

    private var deltaBadge: some View {
        let delta = point.deltaMinutes
        let sign = delta >= 0 ? "+" : "−"
        let value = abs(delta)
        let color: Color = {
            if abs(delta) < 1 { return Theme.labelSecondary }
            return delta > 0 ? Theme.snoring : Theme.good
        }()

        return Text("\(sign)\(minuteLabel(value))")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Difference with habit: \(sign)\(minuteLabel(value))")
    }

    private func minuteLabel(_ minutes: Double) -> String {
        if minutes < 1 { return "<1m" }
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
    }
}
