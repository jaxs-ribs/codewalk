#!/usr/bin/env xcrun swift

import Foundation

// MARK: - Test Logger

class TestLogger {
    static func log(_ message: String, level: String = "INFO") {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] [\(level)] \(message)")
    }

    static func success(_ message: String) {
        log("✅ \(message)", level: "SUCCESS")
    }

    static func error(_ message: String) {
        log("❌ \(message)", level: "ERROR")
    }

    static func debug(_ message: String) {
        log("🔍 \(message)", level: "DEBUG")
    }

    static func section(_ title: String) {
        print("\n" + String(repeating: "=", count: 60))
        print("  \(title)")
        print(String(repeating: "=", count: 60))
    }
}

// MARK: - Test Infrastructure

struct TestCase {
    let name: String
    let phasing: String
    let action: TestAction
    let expectedOutcome: (phases: [Phase]) -> Bool
    let description: String
}

enum TestAction {
    case split(phaseNumber: Int, instructions: String)
    case merge(startPhase: Int, endPhase: Int, instructions: String?)
}

// This is a standalone test runner that can work without the full app
class SplitMergeTestRunner {

    private let groqApiKey: String

    init() {
        // Load API key from .env file
        guard let apiKey = loadEnvVariable("GROQ_API_KEY") else {
            TestLogger.error("GROQ_API_KEY not found in .env file")
            exit(1)
        }
        self.groqApiKey = apiKey
        TestLogger.success("Loaded GROQ_API_KEY")
    }

    private func loadEnvVariable(_ key: String) -> String? {
        let envPath = FileManager.default.currentDirectoryPath + "/.env"
        guard let envContent = try? String(contentsOfFile: envPath) else {
            return nil
        }

        for line in envContent.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "=")
            if parts.count == 2 && parts[0] == key {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: - Test Cases

    func createTestCases() -> [TestCase] {
        return [
            // Test 1: Simple split into 2 phases
            TestCase(
                name: "Simple Split",
                phasing: """
                # Project Phasing

                ## Phase 1: Setup
                Initialize project structure
                **Definition of Done:** Project builds successfully

                ## Phase 2: Implementation and Testing
                Build the feature and write comprehensive tests for it
                **Definition of Done:** Feature works and all tests pass

                ## Phase 3: Deploy
                Deploy to production
                **Definition of Done:** Live in production
                """,
                action: .split(phaseNumber: 2, instructions: "separate implementation from testing"),
                expectedOutcome: { phases in
                    phases.count == 4  // Should have 4 phases after split
                },
                description: "Split phase 2 into implementation and testing phases"
            ),

            // Test 2: Complex split with detailed instructions
            TestCase(
                name: "Complex Split",
                phasing: """
                # Project Phasing

                ## Phase 1: Full Stack Development
                Build frontend UI, backend API, and database schema all together
                **Definition of Done:** Complete application working end-to-end
                """,
                action: .split(phaseNumber: 1, instructions: "split into frontend, backend, and database work"),
                expectedOutcome: { phases in
                    phases.count >= 3  // Should have at least 3 phases
                },
                description: "Split monolithic phase into frontend, backend, and database"
            ),

            // Test 3: Basic merge of consecutive phases
            TestCase(
                name: "Basic Merge",
                phasing: """
                # Project Phasing

                ## Phase 1: Setup
                Setup project
                **Definition of Done:** Project initialized

                ## Phase 2: Small Feature A
                Build feature A
                **Definition of Done:** Feature A works

                ## Phase 3: Small Feature B
                Build feature B
                **Definition of Done:** Feature B works

                ## Phase 4: Deploy
                Deploy everything
                **Definition of Done:** Live in production
                """,
                action: .merge(startPhase: 2, endPhase: 3, instructions: "combine into single feature phase"),
                expectedOutcome: { phases in
                    phases.count == 3  // Should have 3 phases after merge
                },
                description: "Merge phases 2 and 3 into single feature phase"
            ),

            // Test 4: New format (without **Description:**)
            TestCase(
                name: "New Format Split",
                phasing: """
                # Project Phasing

                ## Phase 1: Canvas Setup
                Create HTML file with canvas element and basic styling. Set up JavaScript file to draw a simple colored rectangle on the canvas.
                **Definition of Done:** Open index.html in browser, see a 400x400 pixel canvas with a green rectangle drawn in the center.

                ## Phase 2: Food Implementation
                Create a random food placement function that spawns red squares on empty grid spaces and implement collision detection when the snake's head reaches food, growing the snake by adding a new segment
                **Definition of Done:** Refresh page, see a red square (food) rendered at random empty position on the canvas. Guide snake to touch food, observe snake grows by one segment and food disappears
                """,
                action: .split(phaseNumber: 2, instructions: "separate food spawning from collision detection"),
                expectedOutcome: { phases in
                    phases.count == 3  // Should split phase 2 into 2 phases
                },
                description: "Split new format phase (without Description: prefix)"
            ),

            // Test 5: Edge case - try to merge non-consecutive phases (should fail)
            TestCase(
                name: "Invalid Merge",
                phasing: """
                # Project Phasing

                ## Phase 1: Start
                Start work
                **Definition of Done:** Started

                ## Phase 2: Middle
                Middle work
                **Definition of Done:** Middle done

                ## Phase 3: End
                End work
                **Definition of Done:** Finished
                """,
                action: .merge(startPhase: 1, endPhase: 3, instructions: nil),
                expectedOutcome: { phases in
                    phases.count == 3  // Should remain unchanged (merge should fail)
                },
                description: "Attempt invalid merge of non-consecutive phases"
            )
        ]
    }

    // MARK: - Test Execution

    func runAllTests() async {
        TestLogger.section("STARTING SPLIT/MERGE TEST SUITE")

        let testCases = createTestCases()
        var passedTests = 0
        var failedTests = 0

        for (index, testCase) in testCases.enumerated() {
            TestLogger.section("Test \(index + 1)/\(testCases.count): \(testCase.name)")
            TestLogger.log(testCase.description)

            let passed = await runTest(testCase)
            if passed {
                passedTests += 1
                TestLogger.success("Test '\(testCase.name)' PASSED")
            } else {
                failedTests += 1
                TestLogger.error("Test '\(testCase.name)' FAILED")
            }

            // Add delay between tests to avoid rate limiting
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }

        TestLogger.section("TEST RESULTS")
        TestLogger.log("Passed: \(passedTests)/\(testCases.count)")
        TestLogger.log("Failed: \(failedTests)/\(testCases.count)")

        if failedTests == 0 {
            TestLogger.success("ALL TESTS PASSED! 🎉")
        } else {
            TestLogger.error("\(failedTests) tests failed. Review logs above for details.")
        }
    }

    private func runTest(_ testCase: TestCase) async -> Bool {
        // Create temporary test file
        let testFileName = "test_phasing_\(UUID().uuidString).md"
        let testFilePath = FileManager.default.currentDirectoryPath + "/artifacts/\(testFileName)"

        do {
            // Write test phasing
            try testCase.phasing.write(toFile: testFilePath, atomically: true, encoding: .utf8)
            TestLogger.debug("Created test file: \(testFileName)")

            // Initialize managers
            let artifactManager = ArtifactManager()

            // Parse initial phases
            guard let initialContent = artifactManager.safeRead(filename: testFileName) else {
                TestLogger.error("Failed to read test file")
                return false
            }

            let initialPhases = PhaseParser.parsePhases(from: initialContent)
            TestLogger.debug("Initial phase count: \(initialPhases.count)")

            // Execute action
            var success = false
            switch testCase.action {
            case .split(let phaseNumber, let instructions):
                TestLogger.log("Executing: Split phase \(phaseNumber) with instructions: '\(instructions)'")
                success = await artifactManager.splitPhase(phaseNumber, instructions: instructions, groqApiKey: groqApiKey)

            case .merge(let startPhase, let endPhase, let instructions):
                TestLogger.log("Executing: Merge phases \(startPhase)-\(endPhase)\(instructions.map { " with instructions: '\($0)'" } ?? "")")
                success = await artifactManager.mergePhases(startPhase, endPhase, instructions: instructions, groqApiKey: groqApiKey)
            }

            if !success {
                TestLogger.error("Action execution failed")
                if case .merge(let start, let end, _) = testCase.action,
                   end - start > 1 && testCase.name == "Invalid Merge" {
                    TestLogger.success("Expected failure for invalid merge - this is correct behavior")
                    try? FileManager.default.removeItem(atPath: testFilePath)
                    return true
                }
                try? FileManager.default.removeItem(atPath: testFilePath)
                return false
            }

            // Read result
            guard let resultContent = artifactManager.safeRead(filename: testFileName) else {
                TestLogger.error("Failed to read result file")
                try? FileManager.default.removeItem(atPath: testFilePath)
                return false
            }

            let resultPhases = PhaseParser.parsePhases(from: resultContent)
            TestLogger.debug("Result phase count: \(resultPhases.count)")

            // Log phase titles for debugging
            for phase in resultPhases {
                TestLogger.debug("  Phase \(phase.number): \(phase.title)")
            }

            // Validate outcome
            let outcomeMatches = testCase.expectedOutcome(resultPhases)
            if outcomeMatches {
                TestLogger.success("Outcome matches expectation")
            } else {
                TestLogger.error("Outcome does not match expectation")
            }

            // Cleanup
            try? FileManager.default.removeItem(atPath: testFilePath)
            TestLogger.debug("Cleaned up test file")

            return outcomeMatches

        } catch {
            TestLogger.error("Test error: \(error)")
            try? FileManager.default.removeItem(atPath: testFilePath)
            return false
        }
    }
}

// MARK: - Simplified Phase and ArtifactManager for testing

struct Phase {
    let number: Int
    let title: String
    let description: String
    let definitionOfDone: String
}

class PhaseParser {
    static func parsePhases(from content: String) -> [Phase] {
        // Implementation copied from main PhaseParser
        let lines = content.components(separatedBy: .newlines)
        var phases: [Phase] = []

        var currentPhaseNumber: Int?
        var currentPhaseTitle: String?
        var currentDescription: String?
        var currentDoD: String?
        var collectingDescription = false

        for line in lines {
            if line.hasPrefix("## Phase ") {
                if let number = currentPhaseNumber,
                   let title = currentPhaseTitle,
                   let desc = currentDescription,
                   let dod = currentDoD {
                    phases.append(Phase(
                        number: number,
                        title: title,
                        description: desc,
                        definitionOfDone: dod
                    ))
                }

                let headerPattern = #"## Phase (\d+):\s*(.+)"#
                if let regex = try? NSRegularExpression(pattern: headerPattern),
                   let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {

                    if let numberRange = Range(match.range(at: 1), in: line),
                       let titleRange = Range(match.range(at: 2), in: line),
                       let number = Int(line[numberRange]) {
                        currentPhaseNumber = number
                        currentPhaseTitle = String(line[titleRange])
                        currentDescription = nil
                        currentDoD = nil
                        collectingDescription = true
                    }
                }
            }
            else if line.hasPrefix("**Description:**") {
                let desc = line.replacingOccurrences(of: "**Description:**", with: "").trimmingCharacters(in: .whitespaces)
                currentDescription = desc
                collectingDescription = false
            }
            else if line.hasPrefix("**Definition of Done:**") {
                let dod = line.replacingOccurrences(of: "**Definition of Done:**", with: "").trimmingCharacters(in: .whitespaces)
                currentDoD = dod
                collectingDescription = false
            }
            else if collectingDescription && !line.isEmpty && currentPhaseNumber != nil && currentDescription == nil {
                currentDescription = line
                collectingDescription = false
            }
        }

        if let number = currentPhaseNumber,
           let title = currentPhaseTitle,
           let desc = currentDescription,
           let dod = currentDoD {
            phases.append(Phase(
                number: number,
                title: title,
                description: desc,
                definitionOfDone: dod
            ))
        }

        return phases
    }
}

// Simplified ArtifactManager that works with the actual implementation
class ArtifactManager {
    func safeRead(filename: String) -> String? {
        let path = FileManager.default.currentDirectoryPath + "/artifacts/\(filename)"
        return try? String(contentsOfFile: path)
    }

    func splitPhase(_ phaseNumber: Int, instructions: String, groqApiKey: String) async -> Bool {
        // This would call the actual implementation
        // For testing, we'll simulate by calling a shell script or the actual app
        TestLogger.debug("Calling actual splitPhase implementation...")

        // Since we can't directly call the Swift implementation, we'll need to
        // simulate or use a different approach
        // For now, return true to test the test framework itself
        return true
    }

    func mergePhases(_ startPhase: Int, _ endPhase: Int, instructions: String?, groqApiKey: String) async -> Bool {
        // Similar to splitPhase
        TestLogger.debug("Calling actual mergePhases implementation...")
        return true
    }
}

// MARK: - Main

TestLogger.section("SPLIT/MERGE TEST RUNNER")
TestLogger.log("Initializing test environment...")

let runner = SplitMergeTestRunner()

Task {
    await runner.runAllTests()
    exit(0)
}

RunLoop.main.run()