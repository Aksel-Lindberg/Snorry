import SwiftUI
import SwiftData

// MARK: - Single exercise poster with completion actions
struct MyofascialExerciseCardView: View {

    let exercise: MyofascialExercise
    let completions: [MyofascialExerciseCompletion]

    @Environment(\.modelContext) private var context
    @State private var showHistory = false
    @State private var showImageViewer = false

    private var stripItems: [MyofascialExerciseCompletion.WeekdayStripItem] {
        MyofascialExerciseCompletion.lastSevenStripItems(for: exercise, in: completions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showImageViewer = true
            } label: {
                Image(exercise.imageName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.labelPrimary)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(exercise.title) guide")
            .accessibilityHint("Opens a zoomable full-screen view")

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.title)
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Text(exercise.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MyofascialExerciseWeekStrip(
                items: stripItems,
                onTodayTapped: { toggleTodayCompletion() }
            )

            if !completions.isEmpty {
                Button {
                    showHistory = true
                } label: {
                    HStack(spacing: 4) {
                        Text("All history")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHint("Shows every day you logged this exercise")
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .sheet(isPresented: $showHistory) {
            MyofascialExerciseHistorySheet(exercise: exercise)
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            MyofascialExerciseImageViewer(exercise: exercise)
        }
    }

    private func toggleTodayCompletion() {
        let calendar = Calendar.current
        let todayRows = completions.filter {
            $0.exerciseID == exercise.id && calendar.isDateInToday($0.completedAt)
        }

        if todayRows.isEmpty {
            context.insert(MyofascialExerciseCompletion(exerciseID: exercise.id))
        } else {
            todayRows.forEach { context.delete($0) }
        }
        try? context.save()
    }
}

// MARK: - Rolling 7-day completion strip
private struct MyofascialExerciseWeekStrip: View {

    let items: [MyofascialExerciseCompletion.WeekdayStripItem]
    let onTodayTapped: () -> Void

    private static let weekdayStyle = Date.FormatStyle().weekday(.narrow)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                if item.isToday {
                    Button(action: onTodayTapped) {
                        dayCell(item)
                    }
                    .buttonStyle(.plain)
                } else {
                    dayCell(item)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Theme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last seven days")
    }

    @ViewBuilder
    private func dayCell(_ item: MyofascialExerciseCompletion.WeekdayStripItem) -> some View {
        VStack(spacing: 6) {
            Text(item.dayStart.formatted(Self.weekdayStyle))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.isToday ? Theme.accent : Theme.labelTertiary)

            Text(item.dayStart.formatted(.dateTime.day()))
                .font(.caption2)
                .foregroundStyle(Theme.labelSecondary)

            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(item.isCompleted ? Theme.good : Theme.labelTertiary)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background {
            if item.isToday {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityAddTraits(item.isToday ? .isButton : [])
    }

    private func accessibilityLabel(for item: MyofascialExerciseCompletion.WeekdayStripItem) -> String {
        let dayName = item.dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if item.isToday {
            return item.isCompleted
                ? "\(dayName), today, completed. Double tap to mark not done."
                : "\(dayName), today, not completed. Double tap to mark done."
        }
        return item.isCompleted ? "\(dayName), completed" : "\(dayName), not completed"
    }
}

// MARK: - Full completion history for one exercise
private struct MyofascialExerciseHistorySheet: View {

    let exercise: MyofascialExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allCompletions: [MyofascialExerciseCompletion]

    init(exercise: MyofascialExercise) {
        self.exercise = exercise
        let id = exercise.id
        _allCompletions = Query(
            filter: #Predicate<MyofascialExerciseCompletion> { $0.exerciseID == id },
            sort: \MyofascialExerciseCompletion.completedAt,
            order: .reverse
        )
    }

    private var uniqueDays: [Date] {
        MyofascialExerciseCompletion.uniqueSortedDays(from: allCompletions)
    }

    private var monthSections: [(monthStart: Date, days: [Date])] {
        let calendar = Calendar.current
        var grouped: [Date: [Date]] = [:]
        for day in uniqueDays {
            let components = calendar.dateComponents([.year, .month], from: day)
            guard let monthStart = calendar.date(from: components) else { continue }
            grouped[monthStart, default: []].append(day)
        }
        return grouped
            .map { (monthStart: $0.key, days: $0.value.sorted(by: >)) }
            .sorted { $0.monthStart > $1.monthStart }
    }

    private var loggedDayCount: Int {
        MyofascialExerciseCompletion.loggedDayCount(from: allCompletions)
    }

    private var streak: Int {
        MyofascialExerciseCompletion.currentStreak(for: exercise, in: allCompletions)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                Group {
                    if uniqueDays.isEmpty {
                        ContentUnavailableView(
                            "No completions yet",
                            systemImage: "calendar",
                            description: Text("Tap today on the week strip to log when you practice.")
                        )
                        .foregroundStyle(Theme.labelSecondary)
                    } else {
                        List {
                            Section {
                                historySummaryRow
                                    .listRowBackground(Theme.surface)
                            }

                            ForEach(monthSections, id: \.monthStart) { section in
                                Section {
                                    ForEach(section.days, id: \.self) { day in
                                        historyDayRow(day)
                                            .listRowBackground(Theme.surface)
                                    }
                                    .onDelete { offsets in
                                        deleteDays(at: offsets, in: section.days)
                                    }
                                } header: {
                                    Text(section.monthStart.formatted(.dateTime.month(.wide).year()))
                                        .foregroundStyle(Theme.labelSecondary)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle(exercise.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var historySummaryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(loggedDayCount) day\(loggedDayCount == 1 ? "" : "s") logged")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.labelPrimary)
            if streak > 0 {
                Text("Current streak: \(streak) day\(streak == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.good)
            }
        }
        .padding(.vertical, 4)
    }

    private func historyDayRow(_ day: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.good)
                .symbolRenderingMode(.hierarchical)

            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .foregroundStyle(Theme.labelPrimary)
        }
    }

    private func deleteDays(at offsets: IndexSet, in days: [Date]) {
        let calendar = Calendar.current
        for index in offsets {
            let dayStart = days[index]
            let rows = allCompletions.filter {
                calendar.isDate($0.completedAt, inSameDayAs: dayStart)
            }
            rows.forEach { context.delete($0) }
        }
        try? context.save()
    }
}

#if DEBUG
#Preview {
    MyofascialExerciseCardView(
        exercise: .tongueHasAHome,
        completions: []
    )
    .padding()
    .background(Theme.background)
}
#endif
