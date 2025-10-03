import Foundation

/// Manages persistence of conversation history for sessions
class ConversationHistoryStore {
    private let sessionStore: SessionStore
    private let debugSync: DebugSessionSync

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        self.debugSync = DebugSessionSync()
    }

    /// Save conversation context to session's conversation.json
    func save(_ context: ConversationContext, for sessionId: UUID) {
        let session = Session(id: sessionId)
        let conversationURL = session.conversationPath(in: sessionStore.getBaseURL())

        do {
            try context.saveToFile(url: conversationURL)
            log("Saved conversation for session: \(sessionId)", category: .system, component: "ConversationHistoryStore")

            // Debug sync
            debugSync.syncConversation(for: sessionId, from: conversationURL)
        } catch {
            logError("Failed to save conversation for session \(sessionId): \(error)", component: "ConversationHistoryStore")
        }
    }

    /// Load conversation context from session's conversation.json
    func load(into context: ConversationContext, for sessionId: UUID) {
        let session = Session(id: sessionId)
        let conversationURL = session.conversationPath(in: sessionStore.getBaseURL())

        do {
            try context.loadFromFile(url: conversationURL)
            log("Loaded conversation for session: \(sessionId)", category: .system, component: "ConversationHistoryStore")
        } catch {
            logError("Failed to load conversation for session \(sessionId): \(error)", component: "ConversationHistoryStore")
        }
    }

    /// Check if conversation file exists for session
    func conversationExists(for sessionId: UUID) -> Bool {
        let session = Session(id: sessionId)
        let conversationURL = session.conversationPath(in: sessionStore.getBaseURL())
        return FileManager.default.fileExists(atPath: conversationURL.path)
    }
}
