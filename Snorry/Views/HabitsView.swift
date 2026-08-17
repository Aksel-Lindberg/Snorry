import SwiftUI
import SwiftData

// MARK: - Habits tab — one-tap nightly lifestyle logging
struct HabitsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: \HabitLog.loggedAt, order: .reverse)
    private var allHabitLogs: [HabitLog]

    @Query(sort: \MyofascialExerciseCompletion.completedAt, order: .reverse)
    private var allExerciseCompletions: [MyofascialExerciseCompletion]

    @State private var selectedDayStart: Date = HabitsView.defaultDayStart()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        dayPicker
                        habitGrid
                        footerNote
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 30 : 18)
                    .padding(.vertical, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: horizontalSizeClass == .regular ? 840 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .clearsFloatingTabBar()
            }
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }

    // MARK: - Day selection

    private var dayPicker: some View {
        HStack {
            Button {
                shiftSelectedDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(canGoToPreviousDay ? Theme.accent : Theme.labelTertiary)
            .disabled(!canGoToPreviousDay)

            Spacer()

            VStack(spacing: 4) {
                Text(selectedDayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Text(selectedDaySubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
            }
            .multilineTextAlignment(.center)

            Spacer()

            Button {
                shiftSelectedDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(canGoToNextDay ? Theme.accent : Theme.labelTertiary)
            .disabled(!canGoToNextDay)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Habit buttons

    private var habitGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(HabitKind.allCases) { habit in
                HabitToggleButton(
                    habit: habit,
                    isOn: isHabitOn(habit),
                    action: { toggleHabit(habit) }
                )
            }
        }
    }

    private var footerNote: some View {
        Text(
            "Tap a habit for the night shown above. Logged habits appear in Insights " +
            "alongside your snore duration. Correlation only — not medical advice."
        )
        .font(.footnote)
        .foregroundStyle(Theme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)
    }

    // MARK: - State helpers

    private var calendar: Calendar { Calendar.current }

    private var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    private var canGoToPreviousDay: Bool {
        // Allow browsing back one year of nights.
        guard let earliest = calendar.date(byAdding: .day, value: -365, to: todayStart) else {
            return false
        }
        return selectedDayStart > earliest
    }

    private var canGoToNextDay: Bool {
        selectedDayStart < todayStart
    }

    private var selectedDayTitle: String {
        if calendar.isDateInToday(selectedDayStart) {
            return "Tonight"
        }
        if calendar.isDateInYesterday(selectedDayStart) {
            return "Last night"
        }
        return selectedDayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var selectedDaySubtitle: String {
        selectedDayStart.formatted(date: .abbreviated, time: .omitted)
    }

    private func shiftSelectedDay(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selectedDayStart) else { return }
        selectedDayStart = calendar.startOfDay(for: next)
    }

    private func isHabitOn(_ habit: HabitKind) -> Bool {
        if HabitLog.isLogged(habit: habit, on: selectedDayStart, in: allHabitLogs, calendar: calendar) {
            return true
        }
        // Myofascial exercise also counts when logged from the Exercises tab.
        if habit == .myofascialExercise {
            return hasExerciseCompletion(on: selectedDayStart)
        }
        return false
    }

    private func hasExerciseCompletion(on dayStart: Date) -> Bool {
        allExerciseCompletions.contains {
            calendar.isDate($0.completedAt, inSameDayAs: dayStart)
        }
    }

    private func toggleHabit(_ habit: HabitKind) {
        let dayKey = calendar.startOfDay(for: selectedDayStart)

        if isHabitOn(habit) {
            // Turning off only removes the Habits-tab log — not detailed exercise history.
            if let log = HabitLog.logs(for: dayKey, in: allHabitLogs, calendar: calendar)[habit.id] {
                modelContext.delete(log)
            }
        } else {
            let log = HabitLog(habitID: habit.id, dayStart: dayKey)
            modelContext.insert(log)
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }

    /// Default to yesterday before noon so a morning check-in maps to last night.
    static func defaultDayStart(calendar: Calendar = .current) -> Date {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let hour = calendar.component(.hour, from: now)
        if hour < 12, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            return yesterday
        }
        return today
    }
}

// MARK: - Single habit toggle button
private struct HabitToggleButton: View {
    let habit: HabitKind
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: habit.systemImage)
                    .font(.title3)
                    .foregroundStyle(isOn ? .white : Theme.accent)
                    .symbolRenderingMode(.hierarchical)

                Text(habit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? .white : Theme.labelPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(habit.subtitle)
                    .font(.caption2)
                    .foregroundStyle(isOn ? Color.white.opacity(0.82) : Theme.labelOnSurfaceSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .strokeBorder(
                        isOn ? Color.clear : Theme.accent.opacity(0.22),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(habit.title)
        .accessibilityValue(isOn ? "Logged" : "Not logged")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    HabitsView()
        .modelContainer(for: [HabitLog.self, MyofascialExerciseCompletion.self], inMemory: true)
}
#endif
