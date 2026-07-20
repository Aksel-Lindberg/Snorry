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
            .navigationTitle("Myofascial exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }
}

#if DEBUG
#Preview {
    MyofascialExercisesView()
        .modelContainer(for: MyofascialExerciseCompletion.self, inMemory: true)
}
#endif
