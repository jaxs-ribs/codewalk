import Foundation

/// Test debug sync functionality
@MainActor
class DebugSyncTests {

    func testDebugSync() async {
        print("\n🧪 Testing Debug Sync")
        print("=" * 60)

        // Create a session with artifacts
        let sessionManager = SessionManager()
        sessionManager.initialize()

        let sessionId = sessionManager.activeSessionId!
        print("✅ Created session: \(sessionId)")

        // Add conversation
        let context = sessionManager.conversationContext
        context.addUserMessage("Test message 1")
        context.addAssistantMessage("Test response 1")
        sessionManager.saveCurrentConversation()
        print("✅ Saved conversation with 2 messages")

        // Write an artifact
        let artifactManager = ArtifactManager(groqApiKey: "test-key", sessionId: sessionId)
        let success = artifactManager.safeWrite(filename: "description.md", content: "# Test Description\n\nThis is a test.")
        assert(success, "❌ Failed to write artifact")
        print("✅ Wrote description.md artifact")

        // Check if debug sync worked
        let fileManager = FileManager.default
        let projectRoot = URL(fileURLWithPath: "/Users/fresh/Documents/codewalk/apps/walkingcomputer")
        let debugSessionsPath = projectRoot
            .appendingPathComponent("artifacts")
            .appendingPathComponent("debug-sessions")
            .appendingPathComponent(sessionId.uuidString)

        let activeSessionPath = projectRoot
            .appendingPathComponent("artifacts")
            .appendingPathComponent("active-session")

        // Check session.json exists in debug folder
        let sessionJsonPath = debugSessionsPath.appendingPathComponent("session.json")
        if fileManager.fileExists(atPath: sessionJsonPath.path) {
            print("✅ session.json synced to debug folder")
        } else {
            print("⚠️  session.json not found in debug folder: \(sessionJsonPath.path)")
        }

        // Check conversation.json exists in debug folder
        let conversationJsonPath = debugSessionsPath.appendingPathComponent("conversation.json")
        if fileManager.fileExists(atPath: conversationJsonPath.path) {
            print("✅ conversation.json synced to debug folder")

            // Verify content
            if let data = try? Data(contentsOf: conversationJsonPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("   📊 Contains \(json.count) messages")
            }
        } else {
            print("⚠️  conversation.json not found in debug folder")
        }

        // Check artifact exists in debug folder
        let artifactPath = debugSessionsPath
            .appendingPathComponent("artifacts")
            .appendingPathComponent("description.md")
        if fileManager.fileExists(atPath: artifactPath.path) {
            print("✅ description.md synced to debug folder")

            // Verify content
            if let content = try? String(contentsOf: artifactPath) {
                print("   📝 Content preview: \(content.prefix(50))...")
            }
        } else {
            print("⚠️  description.md not found in debug folder: \(artifactPath.path)")
        }

        // Check active-session symlink
        if fileManager.fileExists(atPath: activeSessionPath.path) {
            print("✅ active-session symlink created")

            // Check if it's actually a symlink
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: activeSessionPath.path) {
                print("   🔗 Points to: \(destination)")
            }
        } else {
            print("⚠️  active-session symlink not found")
        }

        print("\n📂 Debug location:")
        print("   \(debugSessionsPath.path)")
        print("\n🔗 Active session symlink:")
        print("   \(activeSessionPath.path)")

        print("\n💡 Quick access:")
        print("   ls -la \(projectRoot.path)/artifacts/debug-sessions/")
        print("   ls -la \(projectRoot.path)/artifacts/active-session/")
    }

    func runAllTests() async {
        print("\n" + "=" * 60)
        print("🧪 DEBUG SYNC TEST SUITE")
        print("=" * 60)

        await testDebugSync()

        print("\n" + "=" * 60)
        print("✅ DEBUG SYNC TESTS COMPLETE")
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
struct DebugSyncTestRunner {
    static func main() async {
        let tests = DebugSyncTests()
        await tests.runAllTests()
    }
}
