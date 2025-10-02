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
    case "registry":
        runArtifactRegistryTests()
        return

    case "basic":
        let (name, prompts) = TestScripts.basicPhasing()
        await runner.runTest(name: name, prompts: prompts)

    case "write_read":
        let (name, prompts) = TestScripts.writeAndRead()
        await runner.runTest(name: name, prompts: prompts)

    case "edit":
        let (name, prompts) = TestScripts.editPhasing()
        await runner.runTest(name: name, prompts: prompts)

    case "empty":
        let (name, prompts) = TestScripts.emptyConversation()
        await runner.runTest(name: name, prompts: prompts)

    case "router":
        let (name, prompts) = TestScripts.routerCommands()
        await runner.runTest(name: name, prompts: prompts)

    case "all":
        print("Running all tests...\n")

        let tests = [
            TestScripts.basicPhasing(),
            TestScripts.writeAndRead(),
            TestScripts.editPhasing(),
            TestScripts.routerCommands()
            // Skip empty - it's expected to fail/produce minimal output
        ]

        for (name, prompts) in tests {
            await runner.runTest(name: name, prompts: prompts)
            print("\n" + String(repeating: "=", count: 60) + "\n")
        }

    default:
        print("❌ Unknown test: \(testName)")
        print("\nAvailable tests:")
        print("  - registry    : Artifact registry unit tests")
        print("  - basic       : Basic phasing generation")
        print("  - write_read  : Write then read phasing")
        print("  - edit        : Edit existing phasing")
        print("  - empty       : Empty conversation edge case")
        print("  - router      : Router command recognition")
        print("  - all         : Run all tests (except empty)")
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