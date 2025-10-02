import XCTest
@testable import WalkingComputer

class SpecMdTests: XCTestCase {
    var artifactManager: ArtifactManager!
    let testDescription = """
    # Project Description

    ## What We're Building
    A voice-first mobile app that helps you spec projects while walking.

    ## Core Features
    - Voice input and output
    - Real-time transcription
    - Smart project structuring
    """

    let testPhasing = """
    # Project Phasing

    ## Phase 1: Foundation
    Set up the basic voice capture and transcription pipeline.

    **Definition of Done:** Voice input is captured and transcribed accurately.

    ## Phase 2: Processing
    Add intelligent processing to structure the captured content.

    **Definition of Done:** Transcribed content is organized into project specs.
    """

    override func setUp() {
        super.setUp()
        artifactManager = ArtifactManager()

        // Clean up any existing test artifacts
        _ = artifactManager.safeWrite(filename: "spec.md", content: "")
        _ = artifactManager.safeWrite(filename: "description.md", content: "")
        _ = artifactManager.safeWrite(filename: "phasing.md", content: "")
        _ = artifactManager.safeWrite(filename: "description.md.legacy", content: "")
        _ = artifactManager.safeWrite(filename: "phasing.md.legacy", content: "")
    }

    override func tearDown() {
        // Clean up after tests
        _ = artifactManager.safeWrite(filename: "spec.md", content: "")
        _ = artifactManager.safeWrite(filename: "description.md", content: "")
        _ = artifactManager.safeWrite(filename: "phasing.md", content: "")
        _ = artifactManager.safeWrite(filename: "description.md.legacy", content: "")
        _ = artifactManager.safeWrite(filename: "phasing.md.legacy", content: "")
        super.tearDown()
    }

    // MARK: - Basic Read/Write Tests

    func testWriteAndReadSpec() {
        // Write both sections
        let writeSuccess = artifactManager.writeSpec(description: testDescription, phasing: testPhasing)
        XCTAssertTrue(writeSuccess, "Failed to write spec.md")

        // Read back and verify
        let (description, phasing) = artifactManager.readSpec()
        XCTAssertNotNil(description, "Description should not be nil")
        XCTAssertNotNil(phasing, "Phasing should not be nil")
        XCTAssertTrue(description?.contains("What We're Building") ?? false, "Description content mismatch")
        XCTAssertTrue(phasing?.contains("Phase 1: Foundation") ?? false, "Phasing content mismatch")
    }

    func testWriteDescriptionOnly() {
        // Write description only
        let writeSuccess = artifactManager.writeSpecDescription(testDescription)
        XCTAssertTrue(writeSuccess, "Failed to write description to spec.md")

        // Read back and verify
        let (description, phasing) = artifactManager.readSpec()
        XCTAssertNotNil(description, "Description should not be nil")
        XCTAssertNil(phasing, "Phasing should be nil")
        XCTAssertTrue(description?.contains("What We're Building") ?? false, "Description content mismatch")
    }

    func testWritePhasingOnly() {
        // Write phasing only
        let writeSuccess = artifactManager.writeSpecPhasing(testPhasing)
        XCTAssertTrue(writeSuccess, "Failed to write phasing to spec.md")

        // Read back and verify
        let (description, phasing) = artifactManager.readSpec()
        XCTAssertNil(description, "Description should be nil")
        XCTAssertNotNil(phasing, "Phasing should not be nil")
        XCTAssertTrue(phasing?.contains("Phase 1: Foundation") ?? false, "Phasing content mismatch")
    }

    func testUpdateDescriptionPreservesPhasing() {
        // Write initial spec with both sections
        _ = artifactManager.writeSpec(description: testDescription, phasing: testPhasing)

        // Update just the description
        let newDescription = """
        # Project Description

        ## Updated Description
        This is the updated project description.
        """
        let updateSuccess = artifactManager.writeSpecDescription(newDescription)
        XCTAssertTrue(updateSuccess, "Failed to update description")

        // Verify phasing is preserved
        let (description, phasing) = artifactManager.readSpec()
        XCTAssertTrue(description?.contains("Updated Description") ?? false, "Description not updated")
        XCTAssertTrue(phasing?.contains("Phase 1: Foundation") ?? false, "Phasing was lost")
    }

    func testUpdatePhasingPreservesDescription() {
        // Write initial spec with both sections
        _ = artifactManager.writeSpec(description: testDescription, phasing: testPhasing)

        // Update just the phasing
        let newPhasing = """
        # Project Phasing

        ## Phase 1: New Foundation
        Updated phase description.

        **Definition of Done:** New criteria.
        """
        let updateSuccess = artifactManager.writeSpecPhasing(newPhasing)
        XCTAssertTrue(updateSuccess, "Failed to update phasing")

        // Verify description is preserved
        let (description, phasing) = artifactManager.readSpec()
        XCTAssertTrue(description?.contains("What We're Building") ?? false, "Description was lost")
        XCTAssertTrue(phasing?.contains("New Foundation") ?? false, "Phasing not updated")
    }

    // MARK: - Migration Tests

    func testMigrationFromLegacyFiles() {
        // Create legacy files
        _ = artifactManager.safeWrite(filename: "description.md", content: testDescription)
        _ = artifactManager.safeWrite(filename: "phasing.md", content: testPhasing)

        // Trigger migration by reading spec
        let (description, phasing) = artifactManager.readSpec()

        // Verify migration happened
        XCTAssertNotNil(description, "Description should be migrated")
        XCTAssertNotNil(phasing, "Phasing should be migrated")
        XCTAssertTrue(artifactManager.fileExists("spec.md"), "spec.md should be created")
        XCTAssertTrue(artifactManager.fileExists("description.md.legacy"), "Legacy description should be renamed")
        XCTAssertTrue(artifactManager.fileExists("phasing.md.legacy"), "Legacy phasing should be renamed")
    }

    func testMigrationWithOnlyDescription() {
        // Create only legacy description
        _ = artifactManager.safeWrite(filename: "description.md", content: testDescription)

        // Trigger migration
        let (description, phasing) = artifactManager.readSpec()

        // Verify partial migration
        XCTAssertNotNil(description, "Description should be migrated")
        XCTAssertNil(phasing, "Phasing should be nil")
        XCTAssertTrue(artifactManager.fileExists("spec.md"), "spec.md should be created")
    }

    func testMigrationWithOnlyPhasing() {
        // Create only legacy phasing
        _ = artifactManager.safeWrite(filename: "phasing.md", content: testPhasing)

        // Trigger migration
        let (description, phasing) = artifactManager.readSpec()

        // Verify partial migration
        XCTAssertNil(description, "Description should be nil")
        XCTAssertNotNil(phasing, "Phasing should be migrated")
        XCTAssertTrue(artifactManager.fileExists("spec.md"), "spec.md should be created")
    }

    func testNoMigrationWhenSpecExists() {
        // Create spec.md
        _ = artifactManager.writeSpec(description: testDescription, phasing: testPhasing)

        // Create legacy files (should be ignored)
        _ = artifactManager.safeWrite(filename: "description.md", content: "Legacy description")
        _ = artifactManager.safeWrite(filename: "phasing.md", content: "Legacy phasing")

        // Read spec - should not trigger migration
        let (description, phasing) = artifactManager.readSpec()

        // Verify spec.md content is used, not legacy
        XCTAssertTrue(description?.contains("What We're Building") ?? false, "Should use spec.md content")
        XCTAssertFalse(description?.contains("Legacy description") ?? true, "Should not use legacy content")
        XCTAssertFalse(artifactManager.fileExists("description.md.legacy"), "Should not rename when spec exists")
    }

    // MARK: - Section Extraction Tests

    func testExtractSectionsFromCompleteSpec() {
        let completeSpec = """
        # Project Description

        This is the project description.
        It has multiple lines.

        # Project Phasing

        ## Phase 1: Start
        First phase content.

        **Definition of Done:** Phase 1 complete.
        """

        _ = artifactManager.safeWrite(filename: "spec.md", content: completeSpec)
        let (description, phasing) = artifactManager.readSpec()

        XCTAssertNotNil(description)
        XCTAssertNotNil(phasing)
        XCTAssertTrue(description?.contains("Project Description") ?? false)
        XCTAssertTrue(description?.contains("multiple lines") ?? false)
        XCTAssertTrue(phasing?.contains("Project Phasing") ?? false)
        XCTAssertTrue(phasing?.contains("Phase 1: Start") ?? false)
    }

    func testExtractSectionsWithMissingHeaders() {
        let specWithoutHeaders = """
        This is content before any headers.
        It should go to description by default.

        ## Phase 1: Something
        This looks like phasing but has no header.
        """

        _ = artifactManager.safeWrite(filename: "spec.md", content: specWithoutHeaders)
        let (description, phasing) = artifactManager.readSpec()

        XCTAssertNotNil(description)
        XCTAssertNil(phasing)
        XCTAssertTrue(description?.contains("before any headers") ?? false)
        XCTAssertTrue(description?.contains("Phase 1: Something") ?? false)
    }

    // MARK: - Edge Cases

    func testEmptySpec() {
        _ = artifactManager.safeWrite(filename: "spec.md", content: "")
        let (description, phasing) = artifactManager.readSpec()

        XCTAssertNil(description)
        XCTAssertNil(phasing)
    }

    func testWriteEmptyContent() {
        let success = artifactManager.writeSpec(description: "", phasing: "")
        XCTAssertFalse(success, "Should not write empty spec")
    }

    func testLegacyArtifactsCheck() {
        // No artifacts
        XCTAssertFalse(artifactManager.isUsingLegacyArtifacts())

        // Create legacy artifacts
        _ = artifactManager.safeWrite(filename: "description.md", content: "test")
        XCTAssertTrue(artifactManager.isUsingLegacyArtifacts())

        // Create spec.md
        _ = artifactManager.writeSpec(description: "test", phasing: nil)
        XCTAssertFalse(artifactManager.isUsingLegacyArtifacts())
    }

    // MARK: - Performance Tests

    func testLargeSpecPerformance() {
        // Generate large content
        var largeDescription = "# Project Description\n\n"
        var largePhasing = "# Project Phasing\n\n"

        for i in 1...100 {
            largeDescription += "## Section \(i)\nContent for section \(i) with lots of text.\n\n"
            largePhasing += "## Phase \(i): Task \(i)\nPhase \(i) description.\n**Definition of Done:** Criteria \(i)\n\n"
        }

        measure {
            _ = artifactManager.writeSpec(description: largeDescription, phasing: largePhasing)
            _ = artifactManager.readSpec()
        }
    }
}