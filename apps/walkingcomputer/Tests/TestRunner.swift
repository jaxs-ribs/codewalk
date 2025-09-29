import Foundation

// MARK: - Test Runner

@MainActor
class TestRunner {
    private let orchestrator: Orchestrator
    private var testStartTime: Date?

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator
    }

    func runTest(name: String, prompts: [String]) async {
        print("\n🧪 Running test: \(name)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        testStartTime = Date()

        for (index, prompt) in prompts.enumerated() {
            let stepNum = index + 1
            let totalSteps = prompts.count

            print("\n▶️  Step \(stepNum)/\(totalSteps): \"\(prompt)\"")

            let stepStart = Date()

            // Inject the prompt
            await orchestrator.injectPrompt(prompt)

            let duration = Date().timeIntervalSince(stepStart)

            // Print response
            let response = orchestrator.lastResponse
            if !response.isEmpty {
                print("    💬 Response: \"\(response)\"")
            }

            print("    ⏱️  \(String(format: "%.1f", duration))s")
        }

        // Check if artifacts were created
        print("\n📋 Artifacts check:")
        checkArtifact("description.md")
        checkArtifact("phasing.md")

        let totalDuration = Date().timeIntervalSince(testStartTime!)
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ Test completed in \(String(format: "%.1f", totalDuration))s\n")
    }

    private func checkArtifact(_ filename: String) {
        let path = "artifacts/\(filename)"
        if FileManager.default.fileExists(atPath: path) {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let lines = content.split(separator: "\n").count
                let chars = content.count
                print("    ✓ \(filename): \(lines) lines, \(chars) chars")
            } else {
                print("    ⚠️  \(filename): exists but couldn't read")
            }
        } else {
            print("    ✗ \(filename): not found")
        }
    }
}

// MARK: - Test Scripts

struct TestScripts {
    // Test: Basic phasing generation
    static func basicPhasing() -> (String, [String]) {
        return (
            "Basic Phasing Generation",
            [
                "I want to build a todo list app",
                "write the phasing"
            ]
        )
    }

    // Test: Router correctly identifies write vs read
    static func writeAndRead() -> (String, [String]) {
        return (
            "Write Then Read Phasing",
            [
                "I want to build a weather app",
                "write the phasing",
                "read the phasing"
            ]
        )
    }

    // Test: Edit functionality
    static func editPhasing() -> (String, [String]) {
        return (
            "Edit Phasing",
            [
                "I want to build a chat app",
                "write the phasing",
                "edit the phasing to add authentication"
            ]
        )
    }

    // Test: Empty conversation handling
    static func emptyConversation() -> (String, [String]) {
        return (
            "Empty Conversation Phasing",
            [
                "write the phasing"
            ]
        )
    }

    // Test: Router commands (no API cost)
    static func routerCommands() -> (String, [String]) {
        return (
            "Router Command Recognition",
            [
                "I want to build a simple app",
                "write the description",
                "read the description",
                "copy description"
            ]
        )
    }
}