import Foundation
import SwiftUI

// MARK: - App UI theme

enum AppUITheme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    /// Default theme for new installs and invalid stored values.
    static let defaultTheme: AppUITheme = .dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }

    /// `nil` follows the system appearance when `.system` is selected.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }
}

// MARK: - App metadata

enum AppMetadata {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// User-facing version label for Settings (e.g. `1.7 (2)`).
    static var versionLabel: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}

/// Local user preferences stored in UserDefaults (not synced).
enum UserPreferences {

    static let displayNameKey = "userDisplayName"
    /// Set after the user's first visit to the Tonight tab so later visits use a time-of-day greeting.
    static let hasSeenTonightWelcomeKey = "hasSeenTonightWelcome"
    static let appUIThemeKey = "appUITheme"

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
