import Foundation

// MARK: - Built-in or custom habit shown in Habits and Insights
enum HabitDefinition: Identifiable {
    case builtIn(HabitKind)
    case custom(CustomHabit)

    var id: String {
        switch self {
        case .builtIn(let kind): return kind.id
        case .custom(let habit): return habit.logID
        }
    }

    var title: String {
        switch self {
        case .builtIn(let kind): return kind.title
        case .custom(let habit): return habit.title
        }
    }

    var subtitle: String {
        switch self {
        case .builtIn(let kind): return kind.subtitle
        case .custom(let habit):
            return habit.subtitle.isEmpty ? "Your custom habit" : habit.subtitle
        }
    }

    var systemImage: String {
        switch self {
        case .builtIn(let kind): return kind.systemImage
        case .custom: return "tag.fill"
        }
    }

    /// Insights spoken-delta clause.
    var insightClause: String {
        switch self {
        case .builtIn(let kind): return kind.insightClause
        case .custom(let habit): return "on nights you logged \(habit.title)"
        }
    }

    var expectedEffect: HabitExpectedEffect {
        switch self {
        case .builtIn(let kind): return kind.expectedEffect
        case .custom:            return .unknown
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var builtInKind: HabitKind? {
        if case .builtIn(let kind) = self { return kind }
        return nil
    }

    var customHabit: CustomHabit? {
        if case .custom(let habit) = self { return habit }
        return nil
    }

    static func all(customHabits: [CustomHabit]) -> [HabitDefinition] {
        HabitKind.allCases.map { .builtIn($0) } + customHabits.map { .custom($0) }
    }

    static func inSection(_ effect: HabitExpectedEffect, customHabits: [CustomHabit]) -> [HabitDefinition] {
        all(customHabits: customHabits).filter { $0.expectedEffect == effect }
    }
}
