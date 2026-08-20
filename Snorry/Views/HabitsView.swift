import SwiftUI
import SwiftData

// MARK: - Habits tab — one-tap nightly lifestyle logging
struct HabitsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query(sort: \HabitLog.loggedAt, order: .reverse)
    private var allHabitLogs: [HabitLog]

    @Query(sort: \CustomHabit.createdAt)
    private var customHabits: [CustomHabit]

    @Query(sort: \MyofascialExerciseCompletion.completedAt, order: .reverse)
    private var allExerciseCompletions: [MyofascialExerciseCompletion]

    @State private var selectedDayStart: Date = HabitsView.defaultDayStart()
    @State private var editorMode: CustomHabitEditorMode?
    @State private var habitPendingDeletion: CustomHabit?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        dayPicker
                        habitSections
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
            .sheet(item: $editorMode) { mode in
                CustomHabitEditorSheet(mode: mode) { title, subtitle in
                    saveCustomHabit(from: mode, title: title, subtitle: subtitle)
                }
            }
            .alert(
                "Delete custom habit?",
                isPresented: Binding(
                    get: { habitPendingDeletion != nil },
                    set: { if !$0 { habitPendingDeletion = nil } }
                ),
                presenting: habitPendingDeletion
            ) { habit in
                Button("Delete", role: .destructive) {
                    deleteCustomHabit(habit)
                }
                Button("Cancel", role: .cancel) {
                    habitPendingDeletion = nil
                }
            } message: { habit in
                Text("“\(habit.title)” and its logged nights will be removed.")
            }
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

    private var habitSections: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(HabitExpectedEffect.habitsTabSections) { section in
                habitSection(section)
            }
        }
    }

    private func habitSection(_ effect: HabitExpectedEffect) -> some View {
        let habits = HabitDefinition.inSection(effect, customHabits: customHabits)
        let includeAddButton = effect == .unknown

        return VStack(alignment: .leading, spacing: 10) {
            Text(effect.sectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(sectionTitleColor(effect))
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(habits) { habit in
                    habitToggle(habit)
                }

                if includeAddButton {
                    AddCustomHabitButton(isEnabled: customHabits.count < CustomHabit.maxCount) {
                        editorMode = .add
                    }
                }
            }
        }
    }

    private func sectionTitleColor(_ effect: HabitExpectedEffect) -> Color {
        switch effect {
        case .mayAddSnoring: return Theme.snoring
        case .mayHelp:       return Theme.good
        case .unknown:       return Theme.labelSecondary
        }
    }

    private func habitToggle(_ habit: HabitDefinition) -> some View {
        HabitToggleButton(
            title: habit.title,
            subtitle: habit.subtitle,
            systemImage: habit.systemImage,
            isOn: isHabitOn(habit),
            showsCustomBadge: habit.isCustom,
            action: { toggleHabit(habit) }
        )
        .contextMenu {
            if let custom = habit.customHabit {
                Button {
                    editorMode = .edit(custom)
                } label: {
                    Label("Edit habit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    habitPendingDeletion = custom
                } label: {
                    Label("Delete habit", systemImage: "trash")
                }
            }
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "Tap a habit for the night shown above. May add snoring and May help are typical, not a diagnosis. " +
                "Logged habits appear in Insights alongside your snore duration. Correlation only — not medical advice."
            )

            if customHabits.count >= CustomHabit.maxCount {
                Text("Custom habit limit reached (\(CustomHabit.maxCount)). Edit or delete one to add another.")
                    .foregroundStyle(Theme.warning)
            } else {
                Text("Long-press a custom habit to edit or delete it.")
            }
        }
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

    private func isHabitOn(_ habit: HabitDefinition) -> Bool {
        if HabitLog.isLogged(habitID: habit.id, on: selectedDayStart, in: allHabitLogs, calendar: calendar) {
            return true
        }
        if habit.builtInKind == .myofascialExercise {
            return hasExerciseCompletion(on: selectedDayStart)
        }
        return false
    }

    private func hasExerciseCompletion(on dayStart: Date) -> Bool {
        allExerciseCompletions.contains {
            calendar.isDate($0.completedAt, inSameDayAs: dayStart)
        }
    }

    private func toggleHabit(_ habit: HabitDefinition) {
        let dayKey = calendar.startOfDay(for: selectedDayStart)

        if isHabitOn(habit) {
            if let log = HabitLog.logs(for: dayKey, in: allHabitLogs, calendar: calendar)[habit.id] {
                modelContext.delete(log)
            }
        } else {
            let log = HabitLog(habitID: habit.id, dayStart: dayKey)
            modelContext.insert(log)
        }

        saveContext()
    }

    private func saveCustomHabit(from mode: CustomHabitEditorMode, title: String, subtitle: String) {
        guard let sanitized = CustomHabit.sanitized(title: title, subtitle: subtitle) else { return }

        switch mode {
        case .add:
            guard customHabits.count < CustomHabit.maxCount else { return }
            modelContext.insert(
                CustomHabit(title: sanitized.title, subtitle: sanitized.subtitle)
            )
        case .edit(let habit):
            habit.title = sanitized.title
            habit.subtitle = sanitized.subtitle
        }

        saveContext()
        editorMode = nil
    }

    private func deleteCustomHabit(_ habit: CustomHabit) {
        do {
            try HabitLog.deleteLogs(forHabitID: habit.logID, in: modelContext)
            modelContext.delete(habit)
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
        habitPendingDeletion = nil
    }

    private func saveContext() {
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

// MARK: - Custom habit editor modes
private enum CustomHabitEditorMode: Identifiable {
    case add
    case edit(CustomHabit)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let habit): return habit.id.uuidString
        }
    }

    var navigationTitle: String {
        switch self {
        case .add: return "Add custom habit"
        case .edit: return "Edit habit"
        }
    }

    var initialTitle: String {
        switch self {
        case .add: return ""
        case .edit(let habit): return habit.title
        }
    }

    var initialSubtitle: String {
        switch self {
        case .add: return ""
        case .edit(let habit): return habit.subtitle
        }
    }
}

// MARK: - Add custom habit tile
private struct AddCustomHabitButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isEnabled ? Theme.accent : Theme.labelTertiary)

                Text("Add custom habit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isEnabled ? Theme.labelPrimary : Theme.labelTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .strokeBorder(
                        isEnabled ? Theme.accent.opacity(0.35) : Theme.labelTertiary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Add custom habit")
    }
}

// MARK: - Single habit toggle button
private struct HabitToggleButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isOn: Bool
    let showsCustomBadge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(isOn ? .white : Theme.accent)
                        .symbolRenderingMode(.hierarchical)

                    Spacer(minLength: 0)

                    if showsCustomBadge {
                        Text("Custom")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isOn ? Color.white.opacity(0.85) : Theme.labelOnSurfaceSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isOn ? Color.white.opacity(0.18) : Theme.surfaceSecondary)
                            )
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? .white : Theme.labelPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
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
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Logged" : "Not logged")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Add / edit custom habit sheet
private struct CustomHabitEditorSheet: View {
    let mode: CustomHabitEditorMode
    let onSave: (_ title: String, _ subtitle: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String

    init(mode: CustomHabitEditorMode, onSave: @escaping (_ title: String, _ subtitle: String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _title = State(initialValue: mode.initialTitle)
        _subtitle = State(initialValue: mode.initialSubtitle)
    }

    private var canSave: Bool {
        CustomHabit.sanitized(title: title, subtitle: subtitle) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                Form {
                    Section {
                        TextField("Habit name", text: $title)
                            .foregroundStyle(Theme.labelPrimary)
                        TextField("Short note (optional)", text: $subtitle, axis: .vertical)
                            .lineLimit(2...4)
                            .foregroundStyle(Theme.labelPrimary)
                    } footer: {
                        Text(
                            "Examples: Took melatonin, Slept with mouth tape. " +
                            "Up to \(CustomHabit.maxTitleLength) characters."
                        )
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.labelSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, subtitle)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .foregroundStyle(canSave ? Theme.accent : Theme.labelTertiary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#if DEBUG
#Preview {
    HabitsView()
        .modelContainer(
            for: [HabitLog.self, CustomHabit.self, MyofascialExerciseCompletion.self],
            inMemory: true
        )
}
#endif
