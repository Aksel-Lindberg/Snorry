import Foundation

/// Local user preferences stored in UserDefaults (not synced).
enum UserPreferences {

    static let displayNameKey = "userDisplayName"
    /// Set after the user's first visit to the Tonight tab so later visits use a time-of-day greeting.
    static let hasSeenTonightWelcomeKey = "hasSeenTonightWelcome"

    /// Recording-screen greeting — uses first name only when a multi-word name is entered.
    static func goodNightGreeting(displayName: String) -> String {
        personalized(prefix: "Good night", displayName: displayName)
    }

    /// Onboarding consent screen — uses first name only when a multi-word name is entered.
    static func welcomeGreeting(displayName: String) -> String {
        personalized(prefix: "Welcome", displayName: displayName)
    }

    /// Tonight home hero — Welcome on first visit, then morning / afternoon / night.
    static func tonightHomeGreeting(displayName: String, isFirstVisit: Bool, date: Date = Date()) -> String {
        if isFirstVisit {
            return personalized(prefix: "Welcome", displayName: displayName)
        }
        return personalized(prefix: timeOfDayGreeting(for: date), displayName: displayName)
    }

    private static func timeOfDayGreeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good night"
        }
    }

    private static func personalized(prefix: String, displayName: String) -> String {
        guard let firstName = firstName(from: displayName) else { return prefix }
        return "\(prefix), \(firstName)"
    }

    private static func firstName(from displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
    }
}
