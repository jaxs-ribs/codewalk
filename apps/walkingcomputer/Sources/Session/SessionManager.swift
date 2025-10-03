import Foundation
import Combine

/// Centralized session orchestration - manages active session and coordinates persistence
@MainActor
class SessionManager: ObservableObject {
    @Published private(set) var activeSessionId: UUID?
    @Published private(set) var sessions: [Session] = []

    let sessionStore: SessionStore
    private let conversationHistoryStore: ConversationHistoryStore
    private let debugSync: DebugSessionSync
    private(set) var conversationContext: ConversationContext

    init() {
        self.conversationContext = ConversationContext()
        self.sessionStore = SessionStore()
        self.conversationHistoryStore = ConversationHistoryStore(sessionStore: sessionStore)
        self.debugSync = DebugSessionSync()

        log("Initialized", category: .system, component: "SessionManager")
    }

    // MARK: - Initialization

    /// Initialize session management - creates first session if needed
    func initialize() {
        // Log sessions directory path for easy access
        let sessionsPath = sessionStore.getBaseURL().appendingPathComponent("sessions").path
        log("📁 Sessions directory: \(sessionsPath)", category: .system, component: "SessionManager")

        loadSessions()

        if sessions.isEmpty {
            // First launch - create default session
            let session = createSession()
            log("Created first session: \(session.id)", category: .system, component: "SessionManager")
        } else {
            // Load most recent session
            if let mostRecent = sessions.first {
                switchToSession(id: mostRecent.id)
                log("Loaded most recent session: \(mostRecent.id)", category: .system, component: "SessionManager")
            }
        }
    }

    // MARK: - Session Management

    /// Create a new session
    @discardableResult
    func createSession() -> Session {
        // Save current session's conversation if we have one active
        if let currentId = activeSessionId {
            saveCurrentConversation()
            updateSessionTimestamp(currentId)
        }

        let session = sessionStore.createSession()
        sessions.insert(session, at: 0) // Add to front (newest first)

        // Clear conversation context for new session
        conversationContext.clear()

        // Update active session - this triggers the publisher
        activeSessionId = session.id

        // Create symlink to active session for easy debugging
        let sessionPath = sessionStore.getSessionPath(for: session.id)
        debugSync.symlinkActiveSession(session.id, from: sessionPath)

        log("Created and activated session: \(session.id)", category: .system, component: "SessionManager")
        return session
    }

    /// Switch to an existing session
    func switchToSession(id: UUID) {
        // Save current session's conversation if we have one active
        if let currentId = activeSessionId {
            saveCurrentConversation()
            updateSessionTimestamp(currentId)
        }

        // Load new session's conversation
        conversationContext.clear()
        conversationHistoryStore.load(into: conversationContext, for: id)

        // Update active session
        activeSessionId = id
        loadSessions() // Refresh session list

        // Create symlink to active session for easy debugging
        let sessionPath = sessionStore.getSessionPath(for: id)
        debugSync.symlinkActiveSession(id, from: sessionPath)

        log("Switched to session: \(id)", category: .system, component: "SessionManager")
    }

    /// List all sessions (sorted by lastUpdated descending)
    func listSessions() -> [Session] {
        return sessions
    }

    /// Refresh sessions list from disk
    func loadSessions() {
        sessions = sessionStore.listSessions()
        log("Loaded \(sessions.count) sessions", category: .system, component: "SessionManager")
    }

    // MARK: - Conversation Persistence

    /// Save current conversation to active session
    func saveCurrentConversation() {
        guard let sessionId = activeSessionId else {
            logError("Cannot save conversation: no active session", component: "SessionManager")
            return
        }

        conversationHistoryStore.save(conversationContext, for: sessionId)
        log("Saved conversation for session: \(sessionId)", category: .system, component: "SessionManager")
    }

    /// Update session's lastUpdated timestamp
    private func updateSessionTimestamp(_ sessionId: UUID) {
        guard var session = sessions.first(where: { $0.id == sessionId }) else { return }
        sessionStore.updateLastUpdated(&session)

        // Update in local array
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index] = session
        }
    }

    // MARK: - Active Session Info

    /// Get the current active session
    func getActiveSession() -> Session? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    /// Get session ID for artifact operations
    func getActiveSessionId() -> UUID? {
        return activeSessionId
    }
}
