import XCTest
@testable import WalkingComputer

final class SplitMergeIntegrationTests: XCTestCase {

    private var config: EnvConfig!
    private var artifactManager: ArtifactManager!

    override func setUp() async throws {
        try await super.setUp()

        // Load configuration
        config = try EnvConfig.load()

        // Initialize artifact manager
        artifactManager = ArtifactManager()

        // Create test artifacts directory if needed
        let testDir = artifactManager.getFullPath(for: "../test_artifacts")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        print("\n========== Test Setup Complete ==========")
    }

    override func tearDown() async throws {
        // Cleanup test files
        let testDir = artifactManager.getFullPath(for: "../test_artifacts")
        try? FileManager.default.removeItem(at: testDir)

        try await super.tearDown()
    }

    // MARK: - Helper Functions

    private func logTest(_ message: String) {
        print("🧪 TEST: \(message)")
    }

    private func logDebug(_ message: String) {
        print("🔍 DEBUG: \(message)")
    }

    private func logSuccess(_ message: String) {
        print("✅ SUCCESS: \(message)")
    }

    private func logError(_ message: String) {
        print("❌ ERROR: \(message)")
    }

    private func createTestPhasing(_ content: String, filename: String = "test_phasing.md") -> Bool {
        return artifactManager.safeWrite(filename: filename, content: content)
    }

    // MARK: - Test Cases

    func testSplitSimplePhase() async throws {
        logTest("Testing simple phase split")

        let testPhasing = """
        # Project Phasing

        ## Phase 1: Setup Project
        Initialize the project with all necessary dependencies and configurations
        **Definition of Done:** Project builds and runs successfully with all dependencies installed

        ## Phase 2: Build Features
        Implement all the required features for the application
        **Definition of Done:** All features working as specified in requirements
        """

        // Create test file
        XCTAssertTrue(createTestPhasing(testPhasing), "Failed to create test phasing")

        // Read and parse initial phases
        let initialContent = artifactManager.safeRead(filename: "test_phasing.md")
        XCTAssertNotNil(initialContent, "Failed to read initial content")

        let initialPhases = PhaseParser.parsePhases(from: initialContent!)
        logDebug("Initial phase count: \(initialPhases.count)")
        XCTAssertEqual(initialPhases.count, 2, "Should have 2 initial phases")

        // Split phase 1
        let splitSuccess = await artifactManager.splitPhase(
            1,
            instructions: "split into project setup and dependency installation",
            groqApiKey: config.groqApiKey
        )

        XCTAssertTrue(splitSuccess, "Split operation failed")

        // Verify results
        if let resultContent = artifactManager.safeRead(filename: "test_phasing.md") {
            let resultPhases = PhaseParser.parsePhases(from: resultContent)
            logDebug("Result phase count: \(resultPhases.count)")

            for (index, phase) in resultPhases.enumerated() {
                logDebug("Phase \(index + 1): \(phase.title)")
            }

            XCTAssertGreaterThan(resultPhases.count, 2, "Should have more than 2 phases after split")
            logSuccess("Phase split completed successfully")
        } else {
            XCTFail("Failed to read result content")
        }
    }

    func testMergeConsecutivePhases() async throws {
        logTest("Testing consecutive phase merge")

        let testPhasing = """
        # Project Phasing

        ## Phase 1: Setup
        Basic setup
        **Definition of Done:** Setup complete

        ## Phase 2: Feature A
        Build feature A
        **Definition of Done:** Feature A works

        ## Phase 3: Feature B
        Build feature B
        **Definition of Done:** Feature B works

        ## Phase 4: Deploy
        Deploy to production
        **Definition of Done:** Live in production
        """

        // Create test file
        XCTAssertTrue(createTestPhasing(testPhasing, filename: "merge_test.md"), "Failed to create test phasing")

        // Parse initial phases
        let initialContent = artifactManager.safeRead(filename: "merge_test.md")
        XCTAssertNotNil(initialContent)

        let initialPhases = PhaseParser.parsePhases(from: initialContent!)
        logDebug("Initial phase count: \(initialPhases.count)")
        XCTAssertEqual(initialPhases.count, 4, "Should have 4 initial phases")

        // Merge phases 2 and 3
        let mergeSuccess = await artifactManager.mergePhases(
            2, 3,
            instructions: "combine both features into single development phase",
            groqApiKey: config.groqApiKey
        )

        XCTAssertTrue(mergeSuccess, "Merge operation failed")

        // Verify results
        if let resultContent = artifactManager.safeRead(filename: "merge_test.md") {
            let resultPhases = PhaseParser.parsePhases(from: resultContent)
            logDebug("Result phase count: \(resultPhases.count)")

            for (index, phase) in resultPhases.enumerated() {
                logDebug("Phase \(index + 1): \(phase.title)")
            }

            XCTAssertEqual(resultPhases.count, 3, "Should have 3 phases after merge")
            logSuccess("Phase merge completed successfully")
        } else {
            XCTFail("Failed to read result content")
        }
    }

    func testNewFormatPhaseSplit() async throws {
        logTest("Testing new format phase split (no Description: prefix)")

        let testPhasing = """
        # Project Phasing

        ## Phase 1: Canvas Setup
        Create HTML file with canvas element and basic styling. Set up JavaScript file to draw a simple colored rectangle on the canvas.
        **Definition of Done:** Open index.html in browser, see a 400x400 pixel canvas with a green rectangle drawn in the center.

        ## Phase 2: Food Implementation
        Create a random food placement function that spawns red squares on empty grid spaces and implement collision detection when the snake's head reaches food, growing the snake by adding a new segment
        **Definition of Done:** Refresh page, see food and collision detection working
        """

        XCTAssertTrue(createTestPhasing(testPhasing, filename: "new_format_test.md"))

        // Split phase 2
        let splitSuccess = await artifactManager.splitPhase(
            2,
            instructions: "separate food spawning from collision detection",
            groqApiKey: config.groqApiKey
        )

        XCTAssertTrue(splitSuccess, "Split operation failed")

        if let resultContent = artifactManager.safeRead(filename: "new_format_test.md") {
            let resultPhases = PhaseParser.parsePhases(from: resultContent)
            logDebug("Result phase count: \(resultPhases.count)")

            XCTAssertGreaterThan(resultPhases.count, 2, "Should have more phases after split")

            // Verify the split phases have proper content
            for phase in resultPhases {
                XCTAssertFalse(phase.description.isEmpty, "Phase \(phase.number) should have description")
                XCTAssertFalse(phase.definitionOfDone.isEmpty, "Phase \(phase.number) should have DoD")
            }

            logSuccess("New format phase split completed successfully")
        }
    }

    func testInvalidMergeNonConsecutive() async throws {
        logTest("Testing invalid merge of non-consecutive phases")

        let testPhasing = """
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
        """

        XCTAssertTrue(createTestPhasing(testPhasing, filename: "invalid_merge_test.md"))

        let initialContent = artifactManager.safeRead(filename: "invalid_merge_test.md")
        let initialPhases = PhaseParser.parsePhases(from: initialContent!)
        let initialCount = initialPhases.count

        // Try to merge phases 1 and 3 (non-consecutive)
        let mergeSuccess = await artifactManager.mergePhases(
            1, 3,
            instructions: nil,
            groqApiKey: config.groqApiKey
        )

        XCTAssertFalse(mergeSuccess, "Non-consecutive merge should fail")

        // Verify phases remain unchanged
        if let resultContent = artifactManager.safeRead(filename: "invalid_merge_test.md") {
            let resultPhases = PhaseParser.parsePhases(from: resultContent)
            XCTAssertEqual(resultPhases.count, initialCount, "Phase count should remain unchanged")
            logSuccess("Invalid merge correctly rejected")
        }
    }

    func testComplexSplitIntoMultiplePhases() async throws {
        logTest("Testing complex split into multiple phases")

        let testPhasing = """
        # Project Phasing

        ## Phase 1: Full Stack Development
        Build the complete application including frontend UI with React, backend API with Node.js, database schema with PostgreSQL, and deployment pipeline with Docker
        **Definition of Done:** Complete application deployed and running in production
        """

        XCTAssertTrue(createTestPhasing(testPhasing, filename: "complex_split_test.md"))

        // Split into multiple components
        let splitSuccess = await artifactManager.splitPhase(
            1,
            instructions: "split into frontend development, backend API development, database setup, and deployment configuration",
            groqApiKey: config.groqApiKey
        )

        XCTAssertTrue(splitSuccess, "Complex split operation failed")

        if let resultContent = artifactManager.safeRead(filename: "complex_split_test.md") {
            let resultPhases = PhaseParser.parsePhases(from: resultContent)
            logDebug("Result phase count: \(resultPhases.count)")

            // Should have at least 3 phases (could be 4)
            XCTAssertGreaterThanOrEqual(resultPhases.count, 3, "Should have at least 3 phases after complex split")

            for (index, phase) in resultPhases.enumerated() {
                logDebug("Phase \(index + 1): \(phase.title)")
                XCTAssertFalse(phase.title.isEmpty, "Phase title should not be empty")
                XCTAssertFalse(phase.description.isEmpty, "Phase description should not be empty")
            }

            logSuccess("Complex split completed successfully")
        }
    }

    func testBackupCreationOnEdit() async throws {
        logTest("Testing backup creation during edits")

        let testPhasing = """
        # Project Phasing

        ## Phase 1: Test Phase
        This is a test phase
        **Definition of Done:** Test complete
        """

        XCTAssertTrue(createTestPhasing(testPhasing, filename: "backup_test.md"))

        // Get backup directory
        let backupDir = artifactManager.getFullPath(for: "../backups")
        let initialBackups = try? FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            .filter { $0.contains("backup_test.md") }

        // Perform a split to trigger backup
        _ = await artifactManager.splitPhase(
            1,
            instructions: "split into two parts",
            groqApiKey: config.groqApiKey
        )

        // Check for new backup
        let finalBackups = try? FileManager.default.contentsOfDirectory(atPath: backupDir.path)
            .filter { $0.contains("backup_test.md") }

        if let initial = initialBackups, let final = finalBackups {
            XCTAssertGreaterThan(final.count, initial.count, "Should have created a backup")
            logSuccess("Backup created successfully")
        } else if finalBackups?.count ?? 0 > 0 {
            logSuccess("Backup created successfully")
        }
    }

    // MARK: - Performance Test

    func testSplitMergePerformance() async throws {
        logTest("Testing split/merge performance")

        let testPhasing = """
        # Project Phasing

        ## Phase 1: Quick Task
        Do something quickly
        **Definition of Done:** Done quickly
        """

        createTestPhasing(testPhasing, filename: "perf_test.md")

        measure {
            Task {
                // Measure split operation
                _ = await artifactManager.splitPhase(
                    1,
                    instructions: "split into two",
                    groqApiKey: config.groqApiKey
                )
            }
        }

        logSuccess("Performance test completed")
    }
}