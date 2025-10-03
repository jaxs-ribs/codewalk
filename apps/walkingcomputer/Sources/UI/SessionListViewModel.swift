import Foundation
import Combine

@MainActor
class SessionListViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionId: UUID?

    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager

        // Subscribe to session manager updates
        sessionManager.$sessions
            .assign(to: &$sessions)

        sessionManager.$activeSessionId
            .assign(to: &$activeSessionId)

        // Initial load
        refreshSessions()
    }

    func refreshSessions() {
        sessionManager.loadSessions()
    }

    func createNewSession() {
        sessionManager.createSession()
    }

    func switchToSession(_ session: Session) {
        sessionManager.switchToSession(id: session.id)
    }

    func isActiveSession(_ session: Session) -> Bool {
        return session.id == activeSessionId
    }

    /// Format relative time for display
    func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
