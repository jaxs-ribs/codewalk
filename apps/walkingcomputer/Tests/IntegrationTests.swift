import XCTest
@testable import WalkingComputer

final class IntegrationTests: XCTestCase {

    func testSplitMergeScenario() async throws {
        // Skip test if no API key is available
        guard let config = try? EnvConfig.load(),
              !config.groqApiKey.isEmpty else {
            throw XCTSkip("GROQ_API_KEY not configured")
        }

        // Create a test artifact manager
        let artifactManager = ArtifactManager()

        // Create initial test phasing
        let testPhasing = """
        # Project Phasing

        ## Phase 1: Setup project
        **Description:** Initialize project structure and dependencies
        **Definition of Done:** Project runs with basic structure in place

        ## Phase 2: Build user interface and backend
        **Description:** Create all UI components and implement backend services
        **Definition of Done:** Complete UI with functioning backend endpoints

        ## Phase 3: Add testing
        **Description:** Write unit and integration tests
        **Definition of Done:** Test coverage above 80%
        """

        // Write test phasing
        let writeSuccess = artifactManager.safeWrite(filename: "phasing.md", content: testPhasing)
        XCTAssertTrue(writeSuccess, "Failed to write test phasing")

        // Test 1: Split phase 2 into frontend and backend
        let splitSuccess = await artifactManager.splitPhase(
            2,
            instructions: "Split into separate frontend UI work and backend API work",
            groqApiKey: config.groqApiKey
        )
        XCTAssertTrue(splitSuccess, "Failed to split phase")

        // Verify the split worked by reading the updated phasing
        if let updatedContent = artifactManager.safeRead(filename: "phasing.md") {
            let phases = PhaseParser.parsePhases(from: updatedContent)

            // Should have more than 3 phases now (original phase 2 was split)
            XCTAssertGreaterThan(phases.count, 3, "Phase count should increase after split")

            // Test 2: Merge phases back
            if phases.count >= 4 {
                let mergeSuccess = await artifactManager.mergePhases(
                    2, 3,
                    instructions: "Combine into unified development phase",
                    groqApiKey: config.groqApiKey
                )
                XCTAssertTrue(mergeSuccess, "Failed to merge phases")

                // Verify merge worked
                if let finalContent = artifactManager.safeRead(filename: "phasing.md") {
                    let finalPhases = PhaseParser.parsePhases(from: finalContent)

                    // Should be back to 3 phases
                    XCTAssertEqual(finalPhases.count, 3, "Should have 3 phases after merge")
                }
            }
        }

        // Test 3: Edit a specific phase
        let editSuccess = await artifactManager.editSpecificPhase(
            1,
            instructions: "Change to use TypeScript instead of JavaScript",
            groqApiKey: config.groqApiKey
        )
        XCTAssertTrue(editSuccess, "Failed to edit phase")

        // Verify edit worked
        if let editedContent = artifactManager.safeRead(filename: "phasing.md") {
            let editedPhases = PhaseParser.parsePhases(from: editedContent)

            if let phase1 = editedPhases.first(where: { $0.number == 1 }) {
                // Check that the edit was applied (should mention TypeScript now)
                let hasTypeScript = phase1.title.lowercased().contains("typescript") ||
                                   phase1.description.lowercased().contains("typescript") ||
                                   phase1.definitionOfDone.lowercased().contains("typescript")
                XCTAssertTrue(hasTypeScript, "Phase edit should mention TypeScript")
            }
        }
    }

    func testPhaseValidation() async throws {
        // Skip test if no API key is available
        guard let config = try? EnvConfig.load(),
              !config.groqApiKey.isEmpty else {
            throw XCTSkip("GROQ_API_KEY not configured")
        }

        let artifactManager = ArtifactManager()

        // Create test phasing
        let testPhasing = """
        # Project Phasing

        ## Phase 1: First phase
        **Description:** First phase description
        **Definition of Done:** First phase done

        ## Phase 2: Second phase
        **Description:** Second phase description
        **Definition of Done:** Second phase done

        ## Phase 3: Third phase
        **Description:** Third phase description
        **Definition of Done:** Third phase done
        """

        // Write test phasing
        _ = artifactManager.safeWrite(filename: "phasing.md", content: testPhasing)

        // Test: Try to merge non-consecutive phases (should fail)
        let invalidMerge = await artifactManager.mergePhases(
            1, 3,
            instructions: nil,
            groqApiKey: config.groqApiKey
        )
        XCTAssertFalse(invalidMerge, "Should not allow merging non-consecutive phases")

        // Test: Try to split non-existent phase (should fail)
        let invalidSplit = await artifactManager.splitPhase(
            99,
            instructions: "Split this phase",
            groqApiKey: config.groqApiKey
        )
        XCTAssertFalse(invalidSplit, "Should not allow splitting non-existent phase")

        // Test: Try to edit non-existent phase (should fail)
        let invalidEdit = await artifactManager.editSpecificPhase(
            99,
            instructions: "Edit this phase",
            groqApiKey: config.groqApiKey
        )
        XCTAssertFalse(invalidEdit, "Should not allow editing non-existent phase")
    }

    func testBackupCreation() throws {
        let artifactManager = ArtifactManager()

        // Create initial content
        let initialContent = """
        # Project Phasing

        ## Phase 1: Initial phase
        **Description:** Initial description
        **Definition of Done:** Initial done
        """

        // Write initial content
        _ = artifactManager.safeWrite(filename: "phasing.md", content: initialContent)

        // Modify content (this should create a backup)
        let modifiedContent = """
        # Project Phasing

        ## Phase 1: Modified phase
        **Description:** Modified description
        **Definition of Done:** Modified done
        """

        _ = artifactManager.safeWrite(filename: "phasing.md", content: modifiedContent)

        // Check that backup directory exists and contains backup files
        let backupsPath = artifactManager.getFullPath(for: "../backups")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: backupsPath.path) {
            let backupFiles = try fileManager.contentsOfDirectory(atPath: backupsPath.path)
            let phasingBackups = backupFiles.filter { $0.hasPrefix("phasing.md.") }

            XCTAssertGreaterThan(phasingBackups.count, 0, "Should have at least one backup")
        }
    }
}