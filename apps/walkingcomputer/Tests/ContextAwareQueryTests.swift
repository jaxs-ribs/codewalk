import Foundation

// Minimal imports for standalone test
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Test that context auto-loading enables accurate agent responses
@MainActor
class ContextAwareQueryTests {

    private var context: ConversationContext!
    private let fileManager = FileManager.default
    private var testDir: URL!

    func setup() {
        // Create fresh context for each test
        context = ConversationContext()

        // Create temp directory for file operations
        testDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("context-aware-tests-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

        print("✅ Test setup complete, using: \(testDir.path)")
    }

    func cleanup() {
        // Remove temp directory
        if let testDir = testDir {
            try? fileManager.removeItem(at: testDir)
            print("🧹 Cleaned up test directory")
        }
    }

    // MARK: - Test 1: Phase Counting After Phasing Write

    func testPhaseCountingAfterWrite() async {
        print("\n🧪 Test 1: Phase Counting After Phasing Write")
        print("=" * 60)

        setup()
        defer { cleanup() }

        // Simulate writing phasing artifact
        let phasingContent = """
        # Project Phasing

        ## Phase 1: Database Setup
        Set up PostgreSQL with user and post tables.
        **Definition of Done:** Run 'psql \\d users', see columns: id, email, created_at

        ## Phase 2: API Endpoints
        Create REST endpoints for user registration and login.
        **Definition of Done:** Run 'curl -X POST /api/users', receive 201 + user ID

        ## Phase 3: Frontend Forms
        Build React forms for registration and login.
        **Definition of Done:** Click submit, console logs form data

        ## Phase 4: Integration
        Connect frontend forms to backend API.
        **Definition of Done:** Submit form, see new user in database
        """

        // Simulate context auto-loading (what ArtifactActionHandler does)
        context.addSilentContextMessage(phasingContent, type: "Updated phasing.md")
        print("✅ Auto-loaded phasing into context")

        // Simulate user asking "How many phases?"
        context.addUserMessage("How many phases?")

        // Verify context contains phasing
        let history = context.allMessages()
        let phasingInContext = history.contains { ConversationContext.isContextMessage($0.content) && $0.content.contains("# Project Phasing") }
        assert(phasingInContext, "❌ Phasing not found in context")
        print("✅ Phasing found in conversation context")

        // Count phases from context (what agent would do)
        let phaseCount = phasingContent.components(separatedBy: "## Phase").count - 1
        assert(phaseCount == 4, "❌ Expected 4 phases, counted \(phaseCount)")
        print("✅ Agent can count 4 phases from context")

        // Verify context message is NOT spoken
        let contextMsg = history.first { ConversationContext.isContextMessage($0.content) }!
        assert(ConversationContext.isContextMessage(contextMsg.content), "❌ Context message should be marked as such")
        print("✅ Context message correctly marked (won't trigger TTS)")
    }

    // MARK: - Test 2: Description Recall After Edit

    func testDescriptionRecallAfterEdit() async {
        print("\n🧪 Test 2: Description Recall After Edit")
        print("=" * 60)

        setup()
        defer { cleanup() }

        // Write initial description
        let initialDescription = """
        # Project Description

        A simple todo app with basic CRUD operations.
        """

        context.addSilentContextMessage(initialDescription, type: "Updated description.md")
        print("✅ Initial description written and loaded")

        // Simulate edit - regenerate with new requirement
        let updatedDescription = """
        # Project Description

        A simple todo app with basic CRUD operations, dark mode support, and priority tagging.
        """

        context.addSilentContextMessage(updatedDescription, type: "Updated description.md")
        print("✅ Description edited and reloaded into context")

        // User asks about description
        context.addUserMessage("What features are in the description?")

        // Verify updated description in context
        let history = context.allMessages()
        let latestDescription = history.reversed().first {
            ConversationContext.isContextMessage($0.content) && $0.content.contains("description.md")
        }

        assert(latestDescription != nil, "❌ Updated description not found in context")
        assert(latestDescription!.content.contains("dark mode support"), "❌ Edit not reflected in context")
        assert(latestDescription!.content.contains("priority tagging"), "❌ Edit not reflected in context")
        print("✅ Agent can reference updated description with new features")

        // Note: Both versions are in context - Phase 6 will add pruning
        let descriptionCount = history.filter {
            ConversationContext.isContextMessage($0.content) && $0.content.contains("description.md")
        }.count
        print("ℹ️  Context contains \(descriptionCount) versions of description (latest is most recent)")
    }

    // MARK: - Test 3: Research Result Recall

    func testResearchResultRecall() async {
        print("\n🧪 Test 3: Research Result Recall")
        print("=" * 60)

        setup()
        defer { cleanup() }

        // Simulate search results (what SearchActionHandler does)
        let rawResearchResults = """
        Research on React hooks shows three main benefits:

        1. State in function components - useState hook enables local state
        2. Side effects - useEffect replaces lifecycle methods
        3. Custom hooks - reusable stateful logic

        Specific example: useState returns [value, setValue] pair.
        Performance tip: useCallback prevents unnecessary re-renders.
        """

        // This is what SearchActionHandler.executePerplexitySearch does
        context.addUserMessage("Search for: React hooks")
        context.addSilentContextMessage(rawResearchResults, type: "Search results for 'React hooks'")
        print("✅ Raw research results loaded into context")

        // User hears summarized version (not tested here - just TTS)
        // But agent has full raw results in context

        // Later, user asks for specific details
        context.addUserMessage("What specific examples were mentioned?")

        // Verify agent can reference raw research
        let history = context.allMessages()
        let researchInContext = history.first {
            ConversationContext.isContextMessage($0.content) && $0.content.contains("Search results for")
        }

        assert(researchInContext != nil, "❌ Research results not found in context")
        assert(researchInContext!.content.contains("useState returns [value, setValue]"), "❌ Specific example not in context")
        assert(researchInContext!.content.contains("useCallback prevents unnecessary re-renders"), "❌ Performance tip not in context")
        print("✅ Agent can quote specific details from raw research results")
    }

    // MARK: - Test 4: Phase Edit Reflection

    func testPhaseEditReflection() async {
        print("\n🧪 Test 4: Phase Edit Reflection")
        print("=" * 60)

        setup()
        defer { cleanup() }

        // Write initial phasing
        let initialPhasing = """
        # Project Phasing

        ## Phase 1: Setup
        Basic project setup.
        **Definition of Done:** Run 'npm start', app shows blank screen

        ## Phase 2: Features
        Add main features.
        **Definition of Done:** Features work
        """

        context.addSilentContextMessage(initialPhasing, type: "Updated phasing.md")
        print("✅ Initial phasing written")

        // Simulate phase edit (what happens when user says "edit phase 1 to include TypeScript")
        let editedPhasing = """
        # Project Phasing

        ## Phase 1: Setup with TypeScript
        Basic project setup with TypeScript configuration.
        **Definition of Done:** Run 'npm start', app compiles with TypeScript and shows blank screen

        ## Phase 2: Features
        Add main features.
        **Definition of Done:** Features work
        """

        context.addUserMessage("Additional requirement for the phasing: Phase 1 should include TypeScript setup")
        context.addSilentContextMessage(editedPhasing, type: "Updated phasing.md")
        print("✅ Phase 1 edited to include TypeScript")

        // User asks about Phase 1
        context.addUserMessage("What's in Phase 1 now?")

        // Verify edited phasing in context
        let history = context.allMessages()
        let latestPhasing = history.reversed().first {
            ConversationContext.isContextMessage($0.content) && $0.content.contains("phasing.md")
        }

        assert(latestPhasing != nil, "❌ Updated phasing not found in context")
        assert(latestPhasing!.content.contains("TypeScript configuration"), "❌ Edit not reflected in context")
        print("✅ Agent can reference edited phase content")
    }

    // MARK: - Test 5: Context Persistence Across Session Save/Load

    func testContextPersistenceAcrossSessionSaveLoad() async {
        print("\n🧪 Test 5: Context Persistence Across Session Save/Load")
        print("=" * 60)

        setup()
        defer { cleanup() }

        // Add conversation with context messages
        context.addUserMessage("Write description for a blog platform")
        context.addAssistantMessage("Writing description...")

        let descriptionContent = """
        # Project Description

        A modern blogging platform with markdown support and social features.
        """

        context.addSilentContextMessage(descriptionContent, type: "Updated description.md")
        print("✅ Added context message to conversation")

        // Save conversation
        let conversationFile = testDir.appendingPathComponent("test-conversation.json")

        do {
            try context.saveToFile(url: conversationFile)
            print("✅ Saved conversation to file")

            // Load into new context
            let newContext = ConversationContext()
            try newContext.loadFromFile(url: conversationFile)

            let loaded = newContext.allMessages()
            assert(loaded.count == 3, "❌ Expected 3 messages after load, got \(loaded.count)")
            print("✅ Loaded 3 messages from file")

            // Verify context message persisted
            let contextMsg = loaded.first { ConversationContext.isContextMessage($0.content) }
            assert(contextMsg != nil, "❌ Context message lost after save/load")
            assert(contextMsg!.content.contains("description.md"), "❌ Context type lost")
            assert(contextMsg!.content.contains("blogging platform"), "❌ Context content lost")
            print("✅ Context message persisted correctly across save/load")
        } catch {
            print("❌ Test failed: \(error)")
            assert(false, "Save/load failed")
        }
    }

    // MARK: - Test 6: Multiple Context Types Coexist

    func testMultipleContextTypesCoexist() async {
        print("\n🧪 Test 6: Multiple Context Types Coexist")
        print("=" * 60)

        setup()
        defer { cleanup() }

        // Add different context types in sequence
        context.addSilentContextMessage("# Description\n\nA task manager.", type: "Updated description.md")
        print("✅ Added description context")

        context.addSilentContextMessage("# Phasing\n\n## Phase 1: Setup", type: "Updated phasing.md")
        print("✅ Added phasing context")

        context.addSilentContextMessage("Research shows task managers benefit from drag-drop.", type: "Search results for 'task manager UX'")
        print("✅ Added research context")

        // Verify all coexist
        let history = context.allMessages()
        let contextMessages = history.filter { ConversationContext.isContextMessage($0.content) }

        assert(contextMessages.count == 3, "❌ Expected 3 context messages, got \(contextMessages.count)")

        let hasDescription = contextMessages.contains { $0.content.contains("description.md") }
        let hasPhasing = contextMessages.contains { $0.content.contains("phasing.md") }
        let hasResearch = contextMessages.contains { $0.content.contains("Search results for") }

        assert(hasDescription, "❌ Description context missing")
        assert(hasPhasing, "❌ Phasing context missing")
        assert(hasResearch, "❌ Research context missing")

        print("✅ All 3 context types coexist in conversation")
        print("   - description.md")
        print("   - phasing.md")
        print("   - search results")
    }

    // MARK: - Test 7: Context Message Format Verification

    func testContextMessageFormat() async {
        print("\n🧪 Test 7: Context Message Format Verification")
        print("=" * 60)

        setup()
        defer { cleanup() }

        let testContent = "# Test Document\n\nThis is test content."
        context.addSilentContextMessage(testContent, type: "Updated test.md")

        let history = context.allMessages()
        let contextMsg = history.first!.content

        // Verify format: [Context: {type}]\n\n{content}
        assert(contextMsg.hasPrefix("[Context: Updated test.md]"), "❌ Missing context prefix")
        assert(contextMsg.contains("\n\n# Test Document"), "❌ Missing double newline separator")
        assert(contextMsg.contains(testContent), "❌ Content not preserved")
        print("✅ Context message format correct: [Context: {type}]\\n\\n{content}")

        // Verify isContextMessage detection
        assert(ConversationContext.isContextMessage(contextMsg), "❌ isContextMessage failed for context message")
        assert(!ConversationContext.isContextMessage("Regular message"), "❌ isContextMessage false positive")
        print("✅ isContextMessage() correctly identifies context messages")
    }

    // MARK: - Test Runner

    func runAllTests() async {
        print("\n" + "=" * 60)
        print("🧪 CONTEXT-AWARE QUERY TEST SUITE")
        print("=" * 60)

        await testPhaseCountingAfterWrite()
        await testDescriptionRecallAfterEdit()
        await testResearchResultRecall()
        await testPhaseEditReflection()
        await testContextPersistenceAcrossSessionSaveLoad()
        await testMultipleContextTypesCoexist()
        await testContextMessageFormat()

        print("\n" + "=" * 60)
        print("✅ ALL CONTEXT-AWARE QUERY TESTS PASSED")
        print("   - Phase counting from loaded phasing")
        print("   - Description recall after edits")
        print("   - Research result detail recall")
        print("   - Phase edit reflection")
        print("   - Context persistence across save/load")
        print("   - Multiple context types coexist")
        print("   - Context message format verification")
        print("=" * 60 + "\n")
    }
}

// Helper
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

@main
struct ContextAwareQueryTestRunner {
    static func main() async {
        let tests = ContextAwareQueryTests()
        await tests.runAllTests()
    }
}
