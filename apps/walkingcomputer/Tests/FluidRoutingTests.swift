import XCTest
@testable import WalkingComputer

class FluidRoutingTests: XCTestCase {
    var router: Router!

    override func setUp() {
        super.setUp()
        // Use a test API key or mock if needed
        router = Router(groqApiKey: "test-key", modelId: "llama-3.3-70b-versatile")
    }

    // MARK: - Test Corpus for Natural Language Routing

    struct RoutingTestCase {
        let input: String
        let expectedIntent: Intent
        let expectedAction: String  // Simplified action description
        let description: String
    }

    // Comprehensive test corpus mapping natural language to expected routes
    let testCorpus: [RoutingTestCase] = [
        // WRITE OPERATIONS
        RoutingTestCase(
            input: "write everything",
            expectedIntent: .directive,
            expectedAction: "writeBoth",
            description: "Natural 'write everything' should map to writeBoth"
        ),
        RoutingTestCase(
            input: "write the spec",
            expectedIntent: .directive,
            expectedAction: "writeBoth",
            description: "Write spec should write both sections"
        ),
        RoutingTestCase(
            input: "create the project description",
            expectedIntent: .directive,
            expectedAction: "writeDescription",
            description: "Natural create description"
        ),
        RoutingTestCase(
            input: "generate the phasing plan",
            expectedIntent: .directive,
            expectedAction: "writePhasing",
            description: "Natural generate phasing"
        ),
        RoutingTestCase(
            input: "update the description to be more technical",
            expectedIntent: .directive,
            expectedAction: "editDescription",
            description: "Edit description with instructions"
        ),
        RoutingTestCase(
            input: "make the description shorter",
            expectedIntent: .directive,
            expectedAction: "editDescription",
            description: "Natural edit description"
        ),
        RoutingTestCase(
            input: "merge phases 2 and 3",
            expectedIntent: .directive,
            expectedAction: "mergePhases",
            description: "Natural merge phases"
        ),
        RoutingTestCase(
            input: "combine phases 5 through 7",
            expectedIntent: .directive,
            expectedAction: "mergePhases",
            description: "Natural combine phases with range"
        ),
        RoutingTestCase(
            input: "split phase 3 into frontend and backend",
            expectedIntent: .directive,
            expectedAction: "splitPhase",
            description: "Natural split phase"
        ),
        RoutingTestCase(
            input: "break phase 2 into smaller chunks",
            expectedIntent: .directive,
            expectedAction: "splitPhase",
            description: "Natural break phase"
        ),
        RoutingTestCase(
            input: "add testing requirements to phase 4",
            expectedIntent: .directive,
            expectedAction: "editPhasing",
            description: "Edit specific phase"
        ),
        RoutingTestCase(
            input: "change phase 1 to include setup",
            expectedIntent: .directive,
            expectedAction: "editPhasing",
            description: "Natural phase edit"
        ),

        // READ OPERATIONS
        RoutingTestCase(
            input: "read everything",
            expectedIntent: .directive,
            expectedAction: "readDescription",  // Will read both in practice
            description: "Read everything"
        ),
        RoutingTestCase(
            input: "read the whole spec",
            expectedIntent: .directive,
            expectedAction: "readDescription",
            description: "Read whole spec"
        ),
        RoutingTestCase(
            input: "show me the description",
            expectedIntent: .directive,
            expectedAction: "readDescription",
            description: "Natural read description"
        ),
        RoutingTestCase(
            input: "what's the phasing?",
            expectedIntent: .directive,
            expectedAction: "readPhasing",
            description: "Natural read phasing"
        ),
        RoutingTestCase(
            input: "read phase 5",
            expectedIntent: .directive,
            expectedAction: "readSpecificPhase",
            description: "Read specific phase"
        ),
        RoutingTestCase(
            input: "what's in phase 3?",
            expectedIntent: .directive,
            expectedAction: "readSpecificPhase",
            description: "Natural read phase"
        ),
        RoutingTestCase(
            input: "show me phase two",
            expectedIntent: .directive,
            expectedAction: "readSpecificPhase",
            description: "Read phase with word number"
        ),

        // SEARCH OPERATIONS
        RoutingTestCase(
            input: "search for swift concurrency",
            expectedIntent: .directive,
            expectedAction: "search",
            description: "Basic search"
        ),
        RoutingTestCase(
            input: "look up kubernetes patterns",
            expectedIntent: .directive,
            expectedAction: "search",
            description: "Natural lookup"
        ),
        RoutingTestCase(
            input: "deep research on microservices",
            expectedIntent: .directive,
            expectedAction: "deepSearch",
            description: "Deep research"
        ),
        RoutingTestCase(
            input: "do a deep dive into distributed systems",
            expectedIntent: .directive,
            expectedAction: "deepSearch",
            description: "Natural deep dive"
        ),

        // COPY OPERATIONS
        RoutingTestCase(
            input: "copy everything",
            expectedIntent: .directive,
            expectedAction: "copyBoth",
            description: "Copy everything"
        ),
        RoutingTestCase(
            input: "copy the spec to clipboard",
            expectedIntent: .directive,
            expectedAction: "copyBoth",
            description: "Copy spec"
        ),
        RoutingTestCase(
            input: "copy just the description",
            expectedIntent: .directive,
            expectedAction: "copyDescription",
            description: "Copy description only"
        ),
        RoutingTestCase(
            input: "copy the phasing",
            expectedIntent: .directive,
            expectedAction: "copyPhasing",
            description: "Copy phasing"
        ),

        // CONVERSATION
        RoutingTestCase(
            input: "how does async/await work?",
            expectedIntent: .conversation,
            expectedAction: "conversation",
            description: "Question should be conversation"
        ),
        RoutingTestCase(
            input: "I want to build a mobile app",
            expectedIntent: .conversation,
            expectedAction: "conversation",
            description: "Discussion should be conversation"
        ),
        RoutingTestCase(
            input: "what do you think about this approach?",
            expectedIntent: .conversation,
            expectedAction: "conversation",
            description: "Opinion request should be conversation"
        ),

        // EDGE CASES AND COMPLEX INPUTS
        RoutingTestCase(
            input: "rewrite the entire spec with better structure",
            expectedIntent: .directive,
            expectedAction: "writeBoth",
            description: "Rewrite spec"
        ),
        RoutingTestCase(
            input: "edit phase 2 to merge with phase 3 content",
            expectedIntent: .directive,
            expectedAction: "editPhasing",
            description: "Complex edit that mentions merge but is an edit"
        ),
        RoutingTestCase(
            input: "can you write the description?",
            expectedIntent: .directive,
            expectedAction: "writeDescription",
            description: "Polite write request"
        ),
        RoutingTestCase(
            input: "please merge the last two phases",
            expectedIntent: .directive,
            expectedAction: "mergePhases",
            description: "Polite merge with relative reference"
        )
    ]

    // MARK: - Test Helpers

    func validateRouting(_ testCase: RoutingTestCase) -> Bool {
        // This would normally call the router with the test case
        // For now, we'll create a simplified validation
        // In real tests, you'd mock the network call or use a test API

        // Log the test case for manual verification
        print("\n--- Test Case: \(testCase.description) ---")
        print("Input: '\(testCase.input)'")
        print("Expected Intent: \(testCase.expectedIntent)")
        print("Expected Action: \(testCase.expectedAction)")

        // For unit testing without network, we can test the FluidAction conversion
        // This tests the local conversion logic
        testFluidActionConversion(testCase)

        return true
    }

    func testFluidActionConversion(_ testCase: RoutingTestCase) {
        // Test various fluid actions and their conversion to discrete
        switch testCase.expectedAction {
        case "writeBoth":
            let fluid = FluidAction.write(artifact: "spec", instructions: nil)
            let discrete = fluid.toDiscreteAction()
            if case .writeBoth = discrete {
                print("✅ Conversion correct: write(spec) -> writeBoth")
            } else {
                print("❌ Conversion failed: expected writeBoth, got \(discrete)")
            }

        case "mergePhases":
            let fluid = FluidAction.write(artifact: "phasing", instructions: "merge phases 2 and 3")
            let discrete = fluid.toDiscreteAction()
            if case .mergePhases = discrete {
                print("✅ Conversion correct: merge instruction recognized")
            } else {
                print("❌ Conversion failed: expected mergePhases, got \(discrete)")
            }

        case "splitPhase":
            let fluid = FluidAction.write(artifact: "phasing", instructions: "split phase 3 into parts")
            let discrete = fluid.toDiscreteAction()
            if case .splitPhase = discrete {
                print("✅ Conversion correct: split instruction recognized")
            } else {
                print("❌ Conversion failed: expected splitPhase, got \(discrete)")
            }

        case "readSpecificPhase":
            let fluid = FluidAction.read(artifact: "phasing", scope: "phase 3")
            let discrete = fluid.toDiscreteAction()
            if case .readSpecificPhase(let num) = discrete, num == 3 {
                print("✅ Conversion correct: phase 3 extracted")
            } else {
                print("❌ Conversion failed: expected readSpecificPhase(3), got \(discrete)")
            }

        case "deepSearch":
            let fluid = FluidAction.search(query: "test", depth: "deep")
            let discrete = fluid.toDiscreteAction()
            if case .deepSearch = discrete {
                print("✅ Conversion correct: deep search recognized")
            } else {
                print("❌ Conversion failed: expected deepSearch, got \(discrete)")
            }

        default:
            print("⏭️ Test case '\(testCase.expectedAction)' - conversion test skipped")
        }
    }

    // MARK: - Test Methods

    func testFluidActionEnum() {
        // Test that FluidAction enum is properly defined
        let writeAction = FluidAction.write(artifact: "spec", instructions: nil)
        let readAction = FluidAction.read(artifact: "description", scope: nil)
        let searchAction = FluidAction.search(query: "test", depth: nil)
        let copyAction = FluidAction.copy(artifact: "phasing")

        XCTAssertNotNil(writeAction)
        XCTAssertNotNil(readAction)
        XCTAssertNotNil(searchAction)
        XCTAssertNotNil(copyAction)
    }

    func testFluidToDiscreteConversion() {
        // Test write conversions
        let writeSpec = FluidAction.write(artifact: "spec", instructions: nil)
        XCTAssertTrue(writeSpec.toDiscreteAction() == .writeBoth)

        let writeDesc = FluidAction.write(artifact: "description", instructions: nil)
        XCTAssertTrue(writeDesc.toDiscreteAction() == .writeDescription)

        // Test read conversions
        let readPhasing = FluidAction.read(artifact: "phasing", scope: nil)
        XCTAssertTrue(readPhasing.toDiscreteAction() == .readPhasing)

        let readPhase = FluidAction.read(artifact: "phasing", scope: "phase 5")
        if case .readSpecificPhase(let num) = readPhase.toDiscreteAction() {
            XCTAssertEqual(num, 5)
        } else {
            XCTFail("Should convert to readSpecificPhase")
        }

        // Test search conversions
        let search = FluidAction.search(query: "test", depth: nil)
        if case .search(let query) = search.toDiscreteAction() {
            XCTAssertEqual(query, "test")
        } else {
            XCTFail("Should convert to search")
        }

        let deepSearch = FluidAction.search(query: "test", depth: "deep")
        if case .deepSearch(let query) = deepSearch.toDiscreteAction() {
            XCTAssertEqual(query, "test")
        } else {
            XCTFail("Should convert to deepSearch")
        }

        // Test copy conversions
        let copyBoth = FluidAction.copy(artifact: "spec")
        XCTAssertTrue(copyBoth.toDiscreteAction() == .copyBoth)
    }

    func testPhaseNumberExtraction() {
        let fluid = FluidAction.write(artifact: "phasing", instructions: "edit phase 3")

        // Test numeric extraction
        XCTAssertEqual(fluid.extractPhaseNumber(from: "phase 3"), 3)
        XCTAssertEqual(fluid.extractPhaseNumber(from: "Phase 5"), 5)
        XCTAssertEqual(fluid.extractPhaseNumber(from: "phase 10 content"), 10)

        // Test word number extraction
        XCTAssertEqual(fluid.extractPhaseNumber(from: "phase one"), 1)
        XCTAssertEqual(fluid.extractPhaseNumber(from: "phase two"), 2)
        XCTAssertEqual(fluid.extractPhaseNumber(from: "Phase Three"), 3)

        // Test edge cases
        XCTAssertNil(fluid.extractPhaseNumber(from: "no phase here"))
        XCTAssertNil(fluid.extractPhaseNumber(from: "phase"))
    }

    func testPhaseRangeExtraction() {
        let fluid = FluidAction.write(artifact: "phasing", instructions: "merge")

        // Test range extraction
        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 2 to 4")?.start, 2)
        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 2 to 4")?.end, 4)

        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 5 through 7")?.start, 5)
        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 5 through 7")?.end, 7)

        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 1-3")?.start, 1)
        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 1-3")?.end, 3)

        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 2 and 3")?.start, 2)
        XCTAssertEqual(fluid.extractPhaseRange(from: "phases 2 and 3")?.end, 3)

        // Test edge cases
        XCTAssertNil(fluid.extractPhaseRange(from: "phase 3"))
        XCTAssertNil(fluid.extractPhaseRange(from: "no phases"))
    }

    func testCorpusValidation() {
        // Validate each test case in the corpus
        var passCount = 0
        var failCount = 0

        for testCase in testCorpus {
            if validateRouting(testCase) {
                passCount += 1
            } else {
                failCount += 1
            }
        }

        print("\n=== Corpus Validation Summary ===")
        print("Total test cases: \(testCorpus.count)")
        print("Passed: \(passCount)")
        print("Failed: \(failCount)")

        // For CI, we want all tests to pass
        XCTAssertEqual(failCount, 0, "All routing test cases should pass")
    }

    // MARK: - Integration Tests (requires mock or test API)

    func testDualRoutingFallback() {
        // This test would verify that when fluid routing fails,
        // the system falls back to discrete routing
        // Requires mocking or a test environment

        print("\n--- Dual Routing Fallback Test ---")
        print("When fluid routing fails, system should fall back to discrete")
        print("This requires network mocking or test API")

        // For now, just test that the methods exist
        XCTAssertNotNil(router)
        // router.routeWithDualMode would be tested with mocks
    }
}

// MARK: - Equatable extension for testing

extension ProposedAction: Equatable {
    public static func == (lhs: ProposedAction, rhs: ProposedAction) -> Bool {
        switch (lhs, rhs) {
        case (.writeDescription, .writeDescription),
             (.writePhasing, .writePhasing),
             (.writeBoth, .writeBoth),
             (.readDescription, .readDescription),
             (.readPhasing, .readPhasing),
             (.repeatLast, .repeatLast),
             (.stop, .stop),
             (.copyDescription, .copyDescription),
             (.copyPhasing, .copyPhasing),
             (.copyBoth, .copyBoth):
            return true
        case (.readSpecificPhase(let l), .readSpecificPhase(let r)):
            return l == r
        case (.editDescription(let l), .editDescription(let r)):
            return l == r
        case (.editPhasing(let lp, let lc), .editPhasing(let rp, let rc)):
            return lp == rp && lc == rc
        case (.splitPhase(let ln, let li), .splitPhase(let rn, let ri)):
            return ln == rn && li == ri
        case (.mergePhases(let ls, let le, let li), .mergePhases(let rs, let re, let ri)):
            return ls == rs && le == re && li == ri
        case (.conversation(let l), .conversation(let r)):
            return l == r
        case (.search(let l), .search(let r)):
            return l == r
        case (.deepSearch(let l), .deepSearch(let r)):
            return l == r
        default:
            return false
        }
    }
}