import Foundation

// MARK: - Fixed snore-relevant habits (v1 — no custom entries)
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
        case .caffeineLate:        return "Caffeine late"
        case .nasalSpray:          return "Used nasal spray"
        case .nasalClip:           return "Used nasal clip"
        case .myofascialExercise:  return "Myofascial exercise"
        case .congested:           return "Congested"
        case .sleptOnBack:         return "Slept on back"
        }
    }

    var subtitle: String {
        switch self {
        case .ateLate:             return "Meal within ~3 hours of bed"
        case .drankAlcohol:        return "Any alcohol before sleep"
        case .caffeineLate:        return "Coffee, tea, or energy drinks late"
        case .nasalSpray:          return "Decongestant or saline spray"
        case .nasalClip:           return "External nasal dilator or clip"
        case .myofascialExercise:  return "Throat or tongue exercises"
        case .congested:           return "Blocked or stuffy nose"
        case .sleptOnBack:         return "Mostly on your back"
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
}
