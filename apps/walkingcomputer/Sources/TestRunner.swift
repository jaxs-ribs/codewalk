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
    static func basicConversation() -> (String, [String]) {
        return (
            "Basic Conversation",
            [
                "I want to build a simple calculator app",
                "It should support basic operations like add, subtract, multiply, divide",
                "write the phasing"
            ]
        )
    }

    static func dogTinderPhasing() -> (String, [String]) {
        return (
            "Dog Tinder Phasing",
            [
                "I want to build Tinder but for dogs",
                "Dogs swipe by licking the screen",
                "When they bark it's a super like",
                "write the phasing"
            ]
        )
    }

    static func snakeGame() -> (String, [String]) {
        return (
            "Snake Game Phasing",
            [
                "I want to build a snake game in JavaScript",
                "Classic snake with food pellets",
                "Game over when you hit the wall or yourself",
                "write the phasing"
            ]
        )
    }
}