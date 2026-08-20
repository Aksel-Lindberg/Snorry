import SwiftUI
import SwiftData

// MARK: - Myofascial exercises tab
struct MyofascialExercisesView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \MyofascialExerciseCompletion.completedAt, order: .reverse)
    private var allCompletions: [MyofascialExerciseCompletion]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        exerciseReadingTip

                        ForEach(MyofascialExercise.allCases) { exercise in
                            MyofascialExerciseCardView(
                                exercise: exercise,
                                completions: MyofascialExerciseCompletion.completions(
                                    for: exercise,
                                    in: allCompletions
                                )
                            )
                        }
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 30 : 18)
                    .padding(.vertical, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: horizontalSizeClass == .regular ? 840 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .clearsFloatingTabBar()
            }
            .navigationTitle("Airway exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }

    private var exerciseReadingTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.body)
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 2)

            Text(
                "Tap an exercise image to open it full screen. Double-tap to zoom in or out; " +
                    "pinch to resize and drag to pan when zoomed."
            )
            .font(.footnote)
            .foregroundStyle(Theme.labelSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    MyofascialExercisesView()
        .modelContainer(for: MyofascialExerciseCompletion.self, inMemory: true)
}
#endif
