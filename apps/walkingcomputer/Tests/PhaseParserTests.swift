import XCTest
@testable import WalkingComputer

final class PhaseParserTests: XCTestCase {

    func testParsePhases() throws {
        let content = """
        # Project Phasing

        ## Phase 1: Create database schema
        **Description:** Create SQLite database with episodes table
        **Definition of Done:** Run `sqlite3 toilet_tracker.db ".schema episodes"` and see table with columns: id, timestamp, urgency, notes

        ## Phase 2: Build basic logging form
        **Description:** Create HTML form with urgency buttons (1-5) and notes field
        **Definition of Done:** Open index.html, see 5 urgency buttons and notes text input field

        ## Phase 3: Implement database save functionality
        **Description:** Connect form to database to save episode data
        **Definition of Done:** Click urgency level 3, type "test" in notes, submit form, run `sqlite3 toilet_tracker.db "SELECT * FROM episodes"` and see saved row with urgency=3, notes="test"
        """

        let phases = PhaseParser.parsePhases(from: content)

        XCTAssertEqual(phases.count, 3)

        // Check first phase
        XCTAssertEqual(phases[0].number, 1)
        XCTAssertEqual(phases[0].title, "Create database schema")
        XCTAssertEqual(phases[0].description, "Create SQLite database with episodes table")
        XCTAssertTrue(phases[0].definitionOfDone.contains("sqlite3"))

        // Check second phase
        XCTAssertEqual(phases[1].number, 2)
        XCTAssertEqual(phases[1].title, "Build basic logging form")
        XCTAssertEqual(phases[1].description, "Create HTML form with urgency buttons (1-5) and notes field")
        XCTAssertTrue(phases[1].definitionOfDone.contains("index.html"))

        // Check third phase
        XCTAssertEqual(phases[2].number, 3)
        XCTAssertEqual(phases[2].title, "Implement database save functionality")
        XCTAssertEqual(phases[2].description, "Connect form to database to save episode data")
        XCTAssertTrue(phases[2].definitionOfDone.contains("urgency=3"))
    }

    func testPhasesToMarkdown() throws {
        let phases = [
            Phase(
                number: 1,
                title: "Setup project",
                description: "Initialize the project structure",
                definitionOfDone: "Run `npm start` and see welcome page"
            ),
            Phase(
                number: 2,
                title: "Add authentication",
                description: "Implement user login system",
                definitionOfDone: "User can login with email and password"
            )
        ]

        let markdown = PhaseParser.phasesToMarkdown(phases)

        XCTAssertTrue(markdown.contains("# Project Phasing"))
        XCTAssertTrue(markdown.contains("## Phase 1: Setup project"))
        XCTAssertTrue(markdown.contains("**Description:** Initialize the project structure"))
        XCTAssertTrue(markdown.contains("**Definition of Done:** Run `npm start` and see welcome page"))
        XCTAssertTrue(markdown.contains("## Phase 2: Add authentication"))
        XCTAssertTrue(markdown.contains("**Description:** Implement user login system"))
        XCTAssertTrue(markdown.contains("**Definition of Done:** User can login with email and password"))
    }

    func testRenumberPhases() throws {
        let phases = [
            Phase(number: 1, title: "First", description: "First phase", definitionOfDone: "Done 1"),
            Phase(number: 3, title: "Third", description: "Third phase", definitionOfDone: "Done 3"),
            Phase(number: 5, title: "Fifth", description: "Fifth phase", definitionOfDone: "Done 5")
        ]

        let renumbered = PhaseParser.renumberPhases(phases)

        XCTAssertEqual(renumbered.count, 3)
        XCTAssertEqual(renumbered[0].number, 1)
        XCTAssertEqual(renumbered[0].title, "First")
        XCTAssertEqual(renumbered[1].number, 2)
        XCTAssertEqual(renumbered[1].title, "Third")
        XCTAssertEqual(renumbered[2].number, 3)
        XCTAssertEqual(renumbered[2].title, "Fifth")
    }

    func testPhaseToMarkdown() throws {
        let phase = Phase(
            number: 5,
            title: "Deploy to production",
            description: "Deploy the application to production server",
            definitionOfDone: "Application accessible at production URL with all features working"
        )

        let markdown = phase.toMarkdown()

        XCTAssertEqual(markdown, """
        ## Phase 5: Deploy to production
        **Description:** Deploy the application to production server
        **Definition of Done:** Application accessible at production URL with all features working
        """)
    }
}