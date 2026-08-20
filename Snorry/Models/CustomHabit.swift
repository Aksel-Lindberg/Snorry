import Foundation
import SwiftData

// MARK: - User-defined habit (editable and removable)
@Model
final class CustomHabit {

    var id: UUID
    var title: String
    var subtitle: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, subtitle: String = "", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
    }

    /// Stable key stored on `HabitLog.habitID`.
    var logID: String { Self.logID(for: id) }

    static func logID(for id: UUID) -> String {
        "custom.\(id.uuidString)"
    }

    static let maxTitleLength = 40
    static let maxSubtitleLength = 60
    static let maxCount = 20

    /// Normalizes and validates user input before save.
    static func sanitized(title: String, subtitle: String) -> (title: String, subtitle: String)? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            String(trimmedTitle.prefix(maxTitleLength)),
            String(trimmedSubtitle.prefix(maxSubtitleLength))
        )
    }
}
