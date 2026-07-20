import Foundation

// MARK: - Bundled myofascial exercise catalog (fixed order)
enum MyofascialExercise: String, CaseIterable, Identifiable, Sendable {

    case tongueHasAHome
    case mapYourPalate
    case nPositionHold
    case restAndBreathe
    case tongueSuctionHold
    case tongueSuctionClick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tongueHasAHome: return "Your Tongue Has a Home"
        case .mapYourPalate: return "Map Your Palate"
        case .nPositionHold: return "N-Position Hold"
        case .restAndBreathe: return "Rest & Breathe"
        case .tongueSuctionHold: return "Tongue Suction Hold"
        case .tongueSuctionClick: return "Tongue Suction Click"
        }
    }

    var subtitle: String {
        switch self {
        case .tongueHasAHome:
            return "Learn the ideal resting position for your tongue."
        case .mapYourPalate:
            return "Learn where your tongue can reach."
        case .nPositionHold:
            return "Use the “N” sound to find your tongue’s natural resting position."
        case .restAndBreathe:
            return "Practice resting posture while breathing through your nose."
        case .tongueSuctionHold:
            return "Build strength with full tongue-to-palate suction."
        case .tongueSuctionClick:
            return "Build control with a crisp tongue-to-palate click."
        }
    }

    /// Asset catalog image name under Exercises/.
    var imageName: String {
        switch self {
        case .tongueHasAHome: return "ExerciseTongueHasAHome"
        case .mapYourPalate: return "ExerciseMapYourPalate"
        case .nPositionHold: return "ExerciseNPositionHold"
        case .restAndBreathe: return "ExerciseRestAndBreathe"
        case .tongueSuctionHold: return "ExerciseTongueSuctionHold"
        case .tongueSuctionClick: return "ExerciseTongueSuctionClick"
        }
    }
}
