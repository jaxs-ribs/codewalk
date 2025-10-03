import Foundation

/// Test silent context injection
@MainActor
class ContextInjectionTests {

    func testSilentContextInjection() async {
        print("\n🧪 Test: Silent Context Injection")
        print("=" * 60)

        let context = ConversationContext()

        // Add regular messages
        context.addUserMessage("Hello")
        context.addAssistantMessage("Hi there!")

        print("✅ Added 2 regular messages")

        // Add context message
        let artifactContent = "# Test Artifact\n\nThis is test content."
        context.addSilentContextMessage(artifactContent, type: "Updated description.md")

        print("✅ Added silent context message")

        // Verify history
        let history = context.allMessages()
        assert(history.count == 3, "❌ Expected 3 messages, got \(history.count)")
        print("✅ History has 3 messages")

        // Verify context message format
        let contextMsg = history[2].content
        assert(contextMsg.hasPrefix("[Context: Updated description.md]"), "❌ Context message doesn't have correct format")
        assert(contextMsg.contains(artifactContent), "❌ Context message doesn't contain artifact content")
        print("✅ Context message has correct format")

        // Verify isContextMessage works
        assert(ConversationContext.isContextMessage(contextMsg), "❌ isContextMessage failed to detect context message")
        assert(!ConversationContext.isContextMessage("Hi there!"), "❌ isContextMessage incorrectly detected regular message")
        print("✅ isContextMessage() correctly identifies context messages")
    }

    func testContextPersistence() async {
        print("\n🧪 Test: Context Message Persistence")
        print("=" * 60)

        let context = ConversationContext()

        // Add messages including context
        context.addUserMessage("Write a description")
        context.addAssistantMessage("Writing description")
        context.addSilentContextMessage("# Project\n\nA great project.", type: "Updated description.md")

        print("✅ Added 3 messages (1 context)")

        // Save to file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-conversation.json")
        do {
            try context.saveToFile(url: tempURL)
            print("✅ Saved to file")

            // Load into new context
            let newContext = ConversationContext()
            try newContext.loadFromFile(url: tempURL)

            let loaded = newContext.allMessages()
            assert(loaded.count == 3, "❌ Expected 3 messages after load, got \(loaded.count)")
            print("✅ Loaded 3 messages")

            // Verify context message persisted
            let loadedContextMsg = loaded[2].content
            assert(ConversationContext.isContextMessage(loadedContextMsg), "❌ Context message lost after save/load")
            print("✅ Context message persisted correctly")

            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("❌ Failed: \(error)")
            assert(false, "Test failed")
        }
    }

    func testMultipleContextMessages() async {
        print("\n🧪 Test: Multiple Context Messages")
        print("=" * 60)

        let context = ConversationContext()

        // Add multiple context messages
        context.addSilentContextMessage("# Description v1", type: "Updated description.md")
        context.addSilentContextMessage("Phase 1: First phase", type: "Updated phasing.md")
        context.addSilentContextMessage("Research results...", type: "Search results for 'testing'")

        let history = context.allMessages()
        assert(history.count == 3, "❌ Expected 3 context messages, got \(history.count)")

        // Verify all are context messages
        let allContext = history.allSatisfy { ConversationContext.isContextMessage($0.content) }
        assert(allContext, "❌ Not all messages are context messages")

        print("✅ Added 3 different context message types")
        print("   - description.md")
        print("   - phasing.md")
        print("   - search results")
    }

    func runAllTests() async {
        print("\n" + "=" * 60)
        print("🧪 CONTEXT INJECTION TEST SUITE")
        print("=" * 60)

        await testSilentContextInjection()
        await testContextPersistence()
        await testMultipleContextMessages()

        print("\n" + "=" * 60)
        print("✅ ALL CONTEXT INJECTION TESTS PASSED")
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
struct ContextInjectionTestRunner {
    static func main() async {
        let tests = ContextInjectionTests()
        await tests.runAllTests()
    }
}
