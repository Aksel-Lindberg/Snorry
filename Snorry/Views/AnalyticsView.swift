import SwiftUI
import Charts
import SwiftData

// MARK: - Analytics tab root (lazy-initialises the view model)
struct AnalyticsView: View {

    @Environment(\.modelContext) private var context
    @State private var vm: AnalyticsViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()
                if let vm {
                    AnalyticsContent(vm: vm)
                } else {
                    ProgressView().tint(Theme.accent)
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                if vm == nil { vm = AnalyticsViewModel(context: context) }
                vm?.refresh()
            }
        }
    }
}

// MARK: - Scrollable page content
@MainActor
private struct AnalyticsContent: View {

    @Bindable var vm: AnalyticsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                rangePicker
                if !vm.dailyPoints.isEmpty { summaryRow }
                snoreTrendCard
                if !vm.settingsChanges.isEmpty {
                    SettingsChangeLegend(changes: vm.settingsChanges)
                }
                if vm.settingsChanges.isEmpty { markerInfoNote }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
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
            statPill("Avg Snore",    String(format: "%.0f%%", vm.averageSnorePercent), Theme.snoring)
            statPill("Sessions",     "\(vm.sessionCount)",                             Theme.accent)
            statPill("Days Tracked", "\(vm.dailyPoints.count)",                        Theme.good)
        }
    }

    private func statPill(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.monoDigit(size: 20, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.labelTertiary)
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
                SnoreTrendChart(
                    dailyPoints: vm.dailyPoints,
                    settingsChanges: vm.settingsChanges,
                    cutoffDate: vm.cutoffDate,
                    yAxisMax: vm.yAxisMax,
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
                Text("Snore Percentage")
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Text("Daily average · \(vm.selectedRange.rawValue.lowercased())")
                    .font(.caption)
                    .foregroundStyle(Theme.labelTertiary)
            }
            Spacer()
            if !vm.settingsChanges.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(Theme.warning).frame(width: 8, height: 8)
                    Text("Settings changed")
                        .font(.caption2)
                        .foregroundStyle(Theme.labelTertiary)
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
            Text("Start a monitoring session to see your snore trends here.")
                .font(.caption)
                .foregroundStyle(Theme.labelTertiary)
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
                "Settings. This lets you track which Push Notification or Alarm settings " +
                "affected your snore percentage."
            )
            .font(.caption)
            .foregroundStyle(Theme.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Snore trendline chart
private struct SnoreTrendChart: View {

    let dailyPoints: [DailySnorePoint]
    let settingsChanges: [AlertSettingsChange]
    let cutoffDate: Date
    let yAxisMax: Double
    let selectedRange: AnalyticsRange

    var body: some View {
        Chart {
            areaMarks
            lineMarks
            pointMarks
            changeRules
        }
        .chartXScale(domain: cutoffDate...Date())
        .chartYScale(domain: 0...yAxisMax)
        .chartXAxis { xAxisContent }
        .chartYAxis { yAxisContent }
        .frame(height: 240)
    }

    // MARK: Chart marks

    @ChartContentBuilder
    private var areaMarks: some ChartContent {
        ForEach(dailyPoints) { point in
            AreaMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Snore %", point.snorePercent)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.snoring.opacity(0.45), Theme.snoring.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(dailyPoints) { point in
            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Snore %", point.snorePercent)
            )
            .foregroundStyle(Theme.snoring)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        ForEach(dailyPoints) { point in
            PointMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Snore %", point.snorePercent)
            )
            .foregroundStyle(Theme.snoring)
            .symbolSize(35)
            .annotation(position: .top, spacing: 4) {
                Text(String(format: "%.0f%%", point.snorePercent))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.labelSecondary)
            }
        }
    }

    @ChartContentBuilder
    private var changeRules: some ChartContent {
        ForEach(Array(settingsChanges.enumerated()), id: \.offset) { index, change in
            RuleMark(x: .value("Settings changed", change.timestamp))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundStyle(Theme.warning.opacity(0.80))
                .annotation(position: .top, alignment: .center, spacing: 6) {
                    markerBadge(number: index + 1)
                }
        }
    }

    // MARK: Axis content

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
    private var yAxisContent: some AxisContent {
        AxisMarks(preset: .automatic, values: yAxisTickValues) { value in
            AxisGridLine().foregroundStyle(Theme.surfaceSecondary.opacity(0.6))
            AxisValueLabel {
                if let pct = value.as(Double.self) {
                    Text("\(Int(pct))%")
                        .font(.caption2)
                        .foregroundStyle(Theme.labelTertiary)
                }
            }
        }
    }

    // MARK: Axis helpers

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

    private var yAxisTickValues: [Double] {
        [0, 25, 50, 75, 100].filter { $0 <= yAxisMax }
    }

    // MARK: Marker badge

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text("Numbered markers on the chart correspond to rows below.")
                .font(.caption)
                .foregroundStyle(Theme.labelTertiary)
            VStack(spacing: 10) {
                ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                    changeRow(index: index, change: change)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.warning).frame(width: 8, height: 8)
            Text("Settings Changes")
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
