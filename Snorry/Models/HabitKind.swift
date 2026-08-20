import Foundation

// MARK: - Typical direction for a habit (not a diagnosis)
enum HabitExpectedEffect: String, CaseIterable, Identifiable {
    case mayAddSnoring
    case mayHelp
    case unknown

    var id: String { rawValue }

    /// Habits tab section header; Insights chip uses the same wording.
    var sectionTitle: String {
        switch self {
        case .mayAddSnoring: return "May add snoring"
        case .mayHelp:       return "May help"
        case .unknown:       return "Yours"
        }
    }

    /// Insights chip; custom habits have no expected direction.
    var chipTitle: String? {
        switch self {
        case .mayAddSnoring, .mayHelp: return sectionTitle
        case .unknown:                 return nil
        }
    }

    /// Built-in sections first; custom last.
    static var habitsTabSections: [HabitExpectedEffect] {
        [.mayAddSnoring, .mayHelp, .unknown]
    }
}

// MARK: - Fixed snore-relevant habits (built-in set)
enum HabitKind: String, CaseIterable, Identifiable {
    case ateLate
    case drankAlcohol
    case caffeineLate
    case nasalSpray
    case nasalClip
    case myofascialExercise
    case congested
    case sleptOnBack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ateLate:             return "Ate late"
        case .drankAlcohol:        return "Drank alcohol"
        case .caffeineLate:        return "Had caffeine late"
        case .nasalSpray:          return "Used nasal spray"
        case .nasalClip:           return "Used nasal strip"
        case .myofascialExercise:  return "Did airway exercises"
        case .congested:           return "Congested"
        case .sleptOnBack:         return "Slept on your back"
        }
    }

    var subtitle: String {
        switch self {
        case .ateLate:             return "Meal within 3 hours of bed"
        case .drankAlcohol:        return "Any alcohol before bed"
        case .caffeineLate:        return "Coffee, tea, or energy drinks"
        case .nasalSpray:          return "Decongestant or saline"
        case .nasalClip:           return "External strip or clip"
        case .myofascialExercise:  return "Tongue or throat exercises"
        case .congested:           return "Blocked or stuffy nose"
        case .sleptOnBack:         return "Most of the night"
        }
    }

    var systemImage: String {
        switch self {
        case .ateLate:             return "fork.knife"
        case .drankAlcohol:        return "wineglass.fill"
        case .caffeineLate:        return "cup.and.saucer.fill"
        case .nasalSpray:          return "drop.fill"
        case .nasalClip:           return "nose.fill"
        case .myofascialExercise:  return "figure.mind.and.body"
        case .congested:           return "allergens"
        case .sleptOnBack:         return "bed.double.fill"
        }
    }

    /// Typical association used for grouping — not a claim about the user’s nights.
    var expectedEffect: HabitExpectedEffect {
        switch self {
        case .ateLate, .drankAlcohol, .caffeineLate, .congested, .sleptOnBack:
            return .mayAddSnoring
        case .nasalSpray, .nasalClip, .myofascialExercise:
            return .mayHelp
        }
    }

    /// Clause used in Insights delta copy (“+13m on nights you drank alcohol”).
    var insightClause: String {
        switch self {
        case .ateLate:             return "on nights you ate late"
        case .drankAlcohol:        return "on nights you drank alcohol"
        case .caffeineLate:        return "on nights you had caffeine late"
        case .nasalSpray:          return "on nights you used nasal spray"
        case .nasalClip:           return "on nights you used a nasal strip"
        case .myofascialExercise:  return "on nights you did airway exercises"
        case .congested:           return "on nights you were congested"
        case .sleptOnBack:         return "on nights you slept on your back"
        }
    }
}
