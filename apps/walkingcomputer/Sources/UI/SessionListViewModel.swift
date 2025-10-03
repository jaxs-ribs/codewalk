import Foundation
import Combine

@MainActor
class SessionListViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionId: UUID?
    @Published var expandedSessionIds: Set<UUID> = []
    @Published var sessionArtifacts: [UUID: [ArtifactFileNode]] = [:]
    @Published var selectedFile: (session: Session, node: ArtifactFileNode)?

    let sessionManager: SessionManager
    private let artifactScanner = ArtifactFileScanner()
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

    // MARK: - Expansion State

    func toggleExpansion(for session: Session) {
        if expandedSessionIds.contains(session.id) {
            expandedSessionIds.remove(session.id)
        } else {
            expandedSessionIds.insert(session.id)
            // Load artifacts when expanding
            loadArtifacts(for: session)
        }
    }

    func isExpanded(_ session: Session) -> Bool {
        return expandedSessionIds.contains(session.id)
    }

    // MARK: - Artifact Loading

    func loadArtifacts(for session: Session) {
        let baseURL = sessionManager.sessionStore.getBaseURL()
        let artifacts = artifactScanner.scanArtifacts(for: session, baseURL: baseURL)
        sessionArtifacts[session.id] = artifacts
    }

    func getArtifacts(for session: Session) -> [ArtifactFileNode] {
        return sessionArtifacts[session.id] ?? []
    }

    // MARK: - File Selection

    func selectFile(session: Session, node: ArtifactFileNode) {
        selectedFile = (session, node)
    }

    func clearFileSelection() {
        selectedFile = nil
    }
}
