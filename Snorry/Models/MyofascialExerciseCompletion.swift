import Foundation
import SwiftData

// MARK: - Logged completion for a myofascial exercise
@Model
final class MyofascialExerciseCompletion {

    var exerciseID: String
    var completedAt: Date

    init(exerciseID: String, completedAt: Date = Date()) {
        self.exerciseID = exerciseID
        self.completedAt = completedAt
    }
}

extension MyofascialExerciseCompletion {

    static func completions(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion]
    ) -> [MyofascialExerciseCompletion] {
        all.filter { $0.exerciseID == exercise.id }
            .sorted { $0.completedAt > $1.completedAt }
    }

    static func hasCompletionToday(
        for exercise: MyofascialExercise,
        in all: [MyofascialExerciseCompletion],
        calendar: Calendar = .current
    ) -> Bool {
        all.contains {
            $0.exerciseID == exercise.id && calendar.isDateInToday($0.completedAt)
        }
    }
}
