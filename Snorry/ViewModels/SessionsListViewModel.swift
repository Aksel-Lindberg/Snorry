import Foundation
import SwiftData

@Observable
@MainActor
final class SessionsListViewModel {

    var sessions: [SnoreSession] = []
    var isLoading = false

    private let store: SessionStore

    init(context: ModelContext) {
        store = SessionStore(context: context)
    }

    func loadSessions() {
        isLoading = true
        sessions = (try? store.fetchSessions()) ?? []
        isLoading = false
    }

    func deleteSession(_ session: SnoreSession) {
        store.deleteSession(session)
        sessions.removeAll { $0.id == session.id }
    }
}
