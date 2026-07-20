import SwiftUI
import SwiftData

// MARK: - Single exercise poster with completion actions
struct MyofascialExerciseCardView: View {

    let exercise: MyofascialExercise
    let completions: [MyofascialExerciseCompletion]

    @Environment(\.modelContext) private var context
    @State private var showHistory = false
    @State private var showImageViewer = false
    @State private var showAlreadyLoggedToday = false

    private var doneToday: Bool {
        MyofascialExerciseCompletion.hasCompletionToday(for: exercise, in: completions)
    }

    private var lastCompletion: MyofascialExerciseCompletion? {
        completions.first
    }

    private static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)

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

            if showAlreadyLoggedToday {
                Text("Already logged for today.")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
                    .transition(.opacity)
            }

            HStack {
                Spacer()
                calendarButton
                checkmarkButton
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

    private var checkmarkButton: some View {
        Button {
            logCompletionIfAllowed()
        } label: {
            Image(systemName: doneToday ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.title2)
                .foregroundStyle(doneToday ? Theme.good : Theme.accent)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel("Log exercise completion")
        .accessibilityHint(doneToday ? "Completed today" : "Marks this exercise as done for today")
    }

    private var calendarButton: some View {
        Button {
            showHistory = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.body.weight(.medium))
                if let last = lastCompletion {
                    Text("Last: \(last.completedAt.formatted(Self.dateStyle))")
                        .font(.caption)
                } else {
                    Text("No history")
                        .font(.caption)
                }
            }
            .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Completion history")
        .accessibilityHint("Shows dates you logged this exercise")
    }

    private func logCompletionIfAllowed() {
        if doneToday {
            withAnimation { showAlreadyLoggedToday = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation { showAlreadyLoggedToday = false }
                }
            }
            return
        }

        let entry = MyofascialExerciseCompletion(exerciseID: exercise.id)
        context.insert(entry)
        try? context.save()
        showAlreadyLoggedToday = false
    }
}

// MARK: - Completion dates for one exercise
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

    private static let rowDateStyle = Date.FormatStyle(date: .complete, time: .omitted)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                Group {
                    if allCompletions.isEmpty {
                        ContentUnavailableView(
                            "No completions yet",
                            systemImage: "calendar",
                            description: Text("Use the checkmark on the exercise card to log when you practice.")
                        )
                        .foregroundStyle(Theme.labelSecondary)
                    } else {
                        List {
                            ForEach(allCompletions) { entry in
                                Text(entry.completedAt.formatted(Self.rowDateStyle))
                                    .foregroundStyle(Theme.labelPrimary)
                                    .listRowBackground(Theme.surface)
                            }
                            .onDelete(perform: deleteCompletions)
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

    private func deleteCompletions(at offsets: IndexSet) {
        for index in offsets {
            context.delete(allCompletions[index])
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
