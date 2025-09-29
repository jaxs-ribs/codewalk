import Foundation

// Test runner main entry point
// Run with: swift Tests/main.swift [test_name]

@MainActor
func runTests() async {
    print("🧪 Walking Computer Test Runner")
    print("================================\n")

    // Load environment
    let config = EnvConfig.load()

    // Create mock TTS
    let mockTTS = MockTTSManager()

    // Create orchestrator with mock TTS
    let orchestrator = Orchestrator(config: config, ttsManager: mockTTS)

    // Create test runner
    let runner = TestRunner(orchestrator: orchestrator)

    // Get test name from command line
    let testName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "basic"

    // Run the specified test
    switch testName {
    case "basic":
        let (name, prompts) = TestScripts.basicConversation()
        await runner.runTest(name: name, prompts: prompts)

    case "dog_tinder":
        let (name, prompts) = TestScripts.dogTinderPhasing()
        await runner.runTest(name: name, prompts: prompts)

    case "snake":
        let (name, prompts) = TestScripts.snakeGame()
        await runner.runTest(name: name, prompts: prompts)

    case "all":
        print("Running all tests...\n")

        let tests = [
            TestScripts.basicConversation(),
            TestScripts.dogTinderPhasing(),
            TestScripts.snakeGame()
        ]

        for (name, prompts) in tests {
            await runner.runTest(name: name, prompts: prompts)
            print("\n" + String(repeating: "=", count: 60) + "\n")
        }

    default:
        print("❌ Unknown test: \(testName)")
        print("\nAvailable tests:")
        print("  - basic")
        print("  - dog_tinder")
        print("  - snake")
        print("  - all")
        exit(1)
    }

    print("\n✅ All tests completed\n")
}

// Entry point - simple synchronous wrapper
@main
struct TestMain {
    static func main() async {
        await runTests()
    }
}