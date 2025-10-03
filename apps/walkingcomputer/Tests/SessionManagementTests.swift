import Foundation

/// Comprehensive session management tests
@MainActor
class SessionManagementTests {

    // MARK: - Test Setup and Teardown

    private func cleanupSessions() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionsURL = documentsURL.appendingPathComponent("sessions")

        if fileManager.fileExists(atPath: sessionsURL.path) {
            try? fileManager.removeItem(at: sessionsURL)
            print("🧹 Cleaned up sessions directory")
        }
    }

    // MARK: - Test 1: Session Creation and Initialization

    func testSessionCreation() async {
        cleanupSessions()
        print("\n🧪 Test 1: Session Creation and Initialization")
        print("=" * 60)

        let sessionManager = SessionManager()
        sessionManager.initialize()

        // Should auto-create first session
        assert(sessionManager.activeSessionId != nil, "❌ No active session after initialization")
        print("✅ First session auto-created: \(sessionManager.activeSessionId!)")

        let sessions = sessionManager.listSessions()
        assert(sessions.count == 1, "❌ Expected 1 session, got \(sessions.count)")
        print("✅ Session count correct: \(sessions.count)")

        let activeSession = sessionManager.getActiveSession()
        assert(activeSession != nil, "❌ Active session is nil")
        print("✅ Active session retrieved: \(activeSession!.id)")
    }

    // MARK: - Test 2: Conversation Persistence

    func testConversationPersistence() async {
        cleanupSessions()
        print("\n🧪 Test 2: Conversation Persistence")
        print("=" * 60)

        let sessionManager = SessionManager()
        sessionManager.initialize()

        let context = sessionManager.conversationContext

        // Add some messages
        context.addUserMessage("What is the capital of France?")
        context.addAssistantMessage("The capital of France is Paris.")
        context.addUserMessage("Tell me about the Eiffel Tower")
        context.addAssistantMessage("The Eiffel Tower is an iconic landmark in Paris.")

        let originalHistory = context.allMessages()
        assert(originalHistory.count == 4, "❌ Expected 4 messages, got \(originalHistory.count)")
        print("✅ Added 4 messages to conversation")

        // Save conversation
        sessionManager.saveCurrentConversation()
        print("✅ Saved conversation to disk")

        // Clear context
        context.clear()
        assert(context.allMessages().count == 0, "❌ Context not cleared")
        print("✅ Cleared conversation context")

        // Load conversation back
        let sessionId = sessionManager.activeSessionId!
        let historyStore = ConversationHistoryStore(sessionStore: SessionStore())
        historyStore.load(into: context, for: sessionId)

        let loadedHistory = context.allMessages()
        assert(loadedHistory.count == 4, "❌ Expected 4 loaded messages, got \(loadedHistory.count)")
        assert(loadedHistory[0].content == "What is the capital of France?", "❌ First message content mismatch")
        assert(loadedHistory[1].content == "The capital of France is Paris.", "❌ Second message content mismatch")
        print("✅ Loaded conversation correctly with all 4 messages")
    }

    // MARK: - Test 3: Session-Aware Artifact Storage

    func testSessionAwareArtifacts() async {
        cleanupSessions()
        print("\n🧪 Test 3: Session-Aware Artifact Storage")
        print("=" * 60)

        // Create two sessions
        let session1Store = ArtifactStore(sessionId: UUID())
        let session2Store = ArtifactStore(sessionId: UUID())

        // Write different content to same filename in different sessions
        let content1 = "# Session 1 Description\nThis is session 1"
        let content2 = "# Session 2 Description\nThis is session 2"

        let writeSuccess1 = session1Store.write(filename: "description.md", content: content1)
        let writeSuccess2 = session2Store.write(filename: "description.md", content: content2)

        assert(writeSuccess1, "❌ Failed to write to session 1")
        assert(writeSuccess2, "❌ Failed to write to session 2")
        print("✅ Wrote artifacts to two separate sessions")

        // Read back and verify isolation
        let read1 = session1Store.read(filename: "description.md")
        let read2 = session2Store.read(filename: "description.md")

        assert(read1 == content1, "❌ Session 1 content mismatch")
        assert(read2 == content2, "❌ Session 2 content mismatch")
        print("✅ Artifacts correctly isolated between sessions")
        print("   Session 1: \(read1?.prefix(30) ?? "nil")...")
        print("   Session 2: \(read2?.prefix(30) ?? "nil")...")
    }

    // MARK: - Test 4: Session Switching

    func testSessionSwitching() async {
        cleanupSessions()
        print("\n🧪 Test 4: Session Switching")
        print("=" * 60)

        let sessionManager = SessionManager()
        sessionManager.initialize()

        let context = sessionManager.conversationContext

        // Add conversation to first session
        context.addUserMessage("First session message 1")
        context.addAssistantMessage("First session response 1")
        sessionManager.saveCurrentConversation()
        let firstSessionId = sessionManager.activeSessionId!
        print("✅ Created first session with 2 messages: \(firstSessionId)")

        // Create second session
        let secondSession = sessionManager.createSession()
        print("✅ Created second session: \(secondSession.id)")

        // Verify context was cleared
        let messagesAfterCreate = context.allMessages()
        assert(messagesAfterCreate.count == 0, "❌ Context should be empty after creating new session, got \(messagesAfterCreate.count)")
        print("✅ Context cleared for new session")

        // Add different conversation to second session
        context.addUserMessage("Second session message 1")
        context.addAssistantMessage("Second session response 1")
        context.addUserMessage("Second session message 2")
        sessionManager.saveCurrentConversation()
        print("✅ Added 3 messages to second session")

        // Switch back to first session
        sessionManager.switchToSession(id: firstSessionId)
        print("✅ Switched back to first session")

        // Verify first session's conversation is loaded
        let firstSessionMessages = context.allMessages()
        assert(firstSessionMessages.count == 2, "❌ Expected 2 messages in first session, got \(firstSessionMessages.count)")
        assert(firstSessionMessages[0].content == "First session message 1", "❌ First session content mismatch")
        print("✅ First session conversation correctly restored")

        // Switch back to second session
        sessionManager.switchToSession(id: secondSession.id)
        print("✅ Switched to second session")

        // Verify second session's conversation is loaded
        let secondSessionMessages = context.allMessages()
        assert(secondSessionMessages.count == 3, "❌ Expected 3 messages in second session, got \(secondSessionMessages.count)")
        assert(secondSessionMessages[0].content == "Second session message 1", "❌ Second session content mismatch")
        print("✅ Second session conversation correctly restored")
    }

    // MARK: - Test 5: Multiple Sessions Listing

    func testMultipleSessionsListing() async {
        cleanupSessions()
        print("\n🧪 Test 5: Multiple Sessions Listing")
        print("=" * 60)

        let sessionManager = SessionManager()
        sessionManager.initialize()

        // Create multiple sessions
        let session1Id = sessionManager.activeSessionId!
        let session2 = sessionManager.createSession()
        let session3 = sessionManager.createSession()

        print("✅ Created 3 sessions total")

        // List all sessions
        let sessions = sessionManager.listSessions()
        assert(sessions.count == 3, "❌ Expected 3 sessions, got \(sessions.count)")
        print("✅ Listed all 3 sessions")

        // Verify sessions are sorted by lastUpdated (newest first)
        assert(sessions[0].id == session3.id, "❌ Newest session should be first")
        print("✅ Sessions correctly sorted by lastUpdated")

        // Verify we can find specific sessions
        let foundSession = sessions.first { $0.id == session1Id }
        assert(foundSession != nil, "❌ Could not find session1 in list")
        print("✅ Can find specific session in list")
    }

    // MARK: - Test 6: Edge Case - Corrupted Conversation File

    func testCorruptedConversationFile() async {
        cleanupSessions()
        print("\n🧪 Test 6: Edge Case - Corrupted Conversation File")
        print("=" * 60)

        let sessionManager = SessionManager()
        sessionManager.initialize()

        let sessionId = sessionManager.activeSessionId!
        let sessionStore = SessionStore()
        let session = Session(id: sessionId)
        let conversationPath = session.conversationPath(in: sessionStore.getBaseURL())

        // Write corrupted JSON to conversation file
        let corruptedData = "{ this is not valid json }"
        try? corruptedData.write(to: conversationPath, atomically: true, encoding: .utf8)
        print("✅ Wrote corrupted conversation file")

        // Try to load - should handle gracefully
        let context = ConversationContext()
        let historyStore = ConversationHistoryStore(sessionStore: sessionStore)

        // This should not crash
        historyStore.load(into: context, for: sessionId)
        print("✅ Handled corrupted file gracefully (no crash)")

        // Context should be empty since load failed
        let messages = context.allMessages()
        print("   Loaded \(messages.count) messages (expected 0 on corruption)")
    }

    // MARK: - Test 7: Edge Case - Missing Session

    func testMissingSession() async {
        cleanupSessions()
        print("\n🧪 Test 7: Edge Case - Missing Session")
        print("=" * 60)

        let sessionStore = SessionStore()

        // Try to load a session that doesn't exist
        let fakeSessionId = UUID()
        let session = sessionStore.loadSession(id: fakeSessionId)

        assert(session == nil, "❌ Should return nil for missing session")
        print("✅ Correctly returns nil for missing session")

        // Try to check if session exists
        let exists = sessionStore.sessionExists(id: fakeSessionId)
        assert(!exists, "❌ Should return false for missing session")
        print("✅ sessionExists() correctly returns false")
    }

    // MARK: - Test 8: Conversation Context Integration

    func testConversationContextWithSessionManager() async {
        cleanupSessions()
        print("\n🧪 Test 8: Conversation Context Integration")
        print("=" * 60)

        let sessionManager = SessionManager()
        sessionManager.initialize()

        // Get the conversation context owned by session manager
        let context = sessionManager.conversationContext

        // Add messages through context
        context.addUserMessage("Integration test message")
        context.addAssistantMessage("Integration test response")

        // Save through session manager
        sessionManager.saveCurrentConversation()
        print("✅ Saved conversation through SessionManager")

        // Create new SessionManager instance (simulating app restart)
        let newSessionManager = SessionManager()
        newSessionManager.initialize()

        // Should load the most recent session
        let newContext = newSessionManager.conversationContext
        let messages = newContext.allMessages()

        // Should have loaded the saved conversation
        assert(messages.count == 2, "❌ Expected 2 messages after reload, got \(messages.count)")
        assert(messages[0].content == "Integration test message", "❌ Message content mismatch after reload")
        print("✅ Conversation persisted across SessionManager instances")
    }

    // MARK: - Run All Tests

    func runAllTests() async {
        print("\n" + "=" * 60)
        print("🧪 SESSION MANAGEMENT TEST SUITE")
        print("=" * 60)

        do {
            await testSessionCreation()
            await testConversationPersistence()
            await testSessionAwareArtifacts()
            await testSessionSwitching()
            await testMultipleSessionsListing()
            await testCorruptedConversationFile()
            await testMissingSession()
            await testConversationContextWithSessionManager()

            print("\n" + "=" * 60)
            print("✅ ALL TESTS PASSED")
            print("=" * 60 + "\n")
        } catch {
            print("\n" + "=" * 60)
            print("❌ TEST SUITE FAILED: \(error)")
            print("=" * 60 + "\n")
        }
    }
}

// Helper for string repetition
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
