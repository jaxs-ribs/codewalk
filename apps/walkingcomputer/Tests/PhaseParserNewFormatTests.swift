import XCTest
@testable import WalkingComputer

final class PhaseParserNewFormatTests: XCTestCase {

    func testParseNewFormatPhases() throws {
        let content = """
        # Project Phasing

        ## Phase 1: Rust Snake Core - Grid System
        Build the fundamental grid system that will contain our game. This includes creating a 2D coordinate system, grid boundaries, and the ability to track positions within the grid.
        **Definition of Done:** Execute `cargo run --bin grid_test` and see terminal output showing 20x20 grid with (0,0) at top-left and (19,19) at bottom-right.

        ## Phase 2: Rust Snake Core - Snake Movement
        Implement the snake data structure and basic movement mechanics. The snake should be represented as a linked list of body segments that can move in four directions, with collision detection against walls.
        **Definition of Done:** Run `cargo run --bin movement_test`, use arrow keys to move snake around grid, see snake body follow head correctly and game ends when hitting walls.

        ## Phase 3: Rust Snake Core - Food System
        Add the food generation and eating mechanics. Food should spawn at random empty grid positions, and when the snake head collides with food, the snake should grow by one segment and new food should spawn.
        **Definition of Done:** Execute `cargo run --bin food_test`, move snake to food, see snake grow by one segment and new food appear at different location.
        """

        let phases = PhaseParser.parsePhases(from: content)

        XCTAssertEqual(phases.count, 3, "Should parse all 3 phases")

        // Check phase 1
        XCTAssertEqual(phases[0].number, 1)
        XCTAssertEqual(phases[0].title, "Rust Snake Core - Grid System")
        XCTAssertTrue(phases[0].description.contains("fundamental grid system"))
        XCTAssertTrue(phases[0].definitionOfDone.contains("cargo run --bin grid_test"))

        // Check phase 2
        XCTAssertEqual(phases[1].number, 2)
        XCTAssertEqual(phases[1].title, "Rust Snake Core - Snake Movement")
        XCTAssertTrue(phases[1].description.contains("snake data structure"))
        XCTAssertTrue(phases[1].definitionOfDone.contains("cargo run --bin movement_test"))

        // Check phase 3 specifically
        XCTAssertEqual(phases[2].number, 3)
        XCTAssertEqual(phases[2].title, "Rust Snake Core - Food System")
        XCTAssertTrue(phases[2].description.contains("food generation and eating mechanics"))
        XCTAssertTrue(phases[2].definitionOfDone.contains("cargo run --bin food_test"))

        // Ensure descriptions are not empty
        for phase in phases {
            XCTAssertFalse(phase.description.isEmpty, "Phase \(phase.number) description should not be empty")
            XCTAssertFalse(phase.definitionOfDone.isEmpty, "Phase \(phase.number) DoD should not be empty")
        }
    }

    func testMixedFormatPhases() throws {
        // Test that both old and new formats work together
        let content = """
        # Project Phasing

        ## Phase 1: Old Format Phase
        **Description:** This uses the old format with explicit Description tag
        **Definition of Done:** Old format DoD

        ## Phase 2: New Format Phase
        This is a new format phase where the description is just a paragraph.
        **Definition of Done:** New format DoD
        """

        let phases = PhaseParser.parsePhases(from: content)

        XCTAssertEqual(phases.count, 2, "Should parse both format phases")

        // Check old format phase
        XCTAssertEqual(phases[0].title, "Old Format Phase")
        XCTAssertEqual(phases[0].description, "This uses the old format with explicit Description tag")
        XCTAssertEqual(phases[0].definitionOfDone, "Old format DoD")

        // Check new format phase
        XCTAssertEqual(phases[1].title, "New Format Phase")
        XCTAssertEqual(phases[1].description, "This is a new format phase where the description is just a paragraph.")
        XCTAssertEqual(phases[1].definitionOfDone, "New format DoD")
    }
}