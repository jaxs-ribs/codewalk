#!/usr/bin/env swift

import Foundation

// MARK: - Simplified copies for testing

enum UserIntent {
    case read, question, write, edit, unknown
}

struct IntentParser {
    static func parse(_ input: String) -> UserIntent {
        let lower = input.lowercased()
        if lower.hasPrefix("read ") { return .read }
        if lower.hasPrefix("how many ") || lower.hasPrefix("what are ") { return .question }
        if lower.hasPrefix("write ") { return .write }
        if lower.hasPrefix("edit ") { return .edit }
        return .unknown
    }
}

struct Artifact: Equatable {
    let path: String
    let keywords: [String]
    let summary: String
}

class ArtifactRegistry {
    private var artifacts: [Artifact] = []

    func add(_ artifact: Artifact) {
        artifacts.append(artifact)
    }

    func match(input: String, threshold: Double) -> [Artifact] {
        let tokens = input.lowercased().components(separatedBy: " ")

        return artifacts.filter { artifact in
            var score = 0.0
            for token in tokens {
                if artifact.keywords.contains(token) {
                    score += 10.0
                }
                if artifact.summary.lowercased().contains(token) {
                    score += 1.0
                }
            }
            return score >= threshold
        }
    }
}

class SimpleRouter {
    private let registry: ArtifactRegistry?

    init(registry: ArtifactRegistry? = nil) {
        self.registry = registry
    }

    func checkForContextLoading(transcript: String) -> [String]? {
        guard let registry = registry else {
            return nil
        }

        let intent = IntentParser.parse(transcript)

        guard intent == .question else {
            return nil
        }

        let matches = registry.match(input: transcript, threshold: 5.0)

        guard !matches.isEmpty else {
            return nil
        }

        return Array(matches.prefix(2)).map { $0.path }
    }
}

// MARK: - Tests

func testRouterWithoutRegistry() {
    let router = SimpleRouter(registry: nil)

    let result = router.checkForContextLoading(transcript: "how many phases")

    assert(result == nil, "Router without registry should return nil")

    print("✅ testRouterWithoutRegistry passed")
}

func testRouterWithRegistry_MatchesQuestion() {
    let registry = ArtifactRegistry()

    let phasing = Artifact(
        path: "artifacts/phasing.md",
        keywords: ["phasing", "phases", "plan"],
        summary: "Project phasing plan"
    )
    registry.add(phasing)

    let router = SimpleRouter(registry: registry)

    let result = router.checkForContextLoading(transcript: "how many phases")

    assert(result != nil, "Should propose context loading for question about phases")
    assert(result == ["artifacts/phasing.md"], "Should match phasing artifact")

    print("✅ testRouterWithRegistry_MatchesQuestion passed")
}

func testRouterWithRegistry_NonQuestionIgnored() {
    let registry = ArtifactRegistry()

    let phasing = Artifact(
        path: "artifacts/phasing.md",
        keywords: ["phasing", "phases"],
        summary: "Project phasing plan"
    )
    registry.add(phasing)

    let router = SimpleRouter(registry: registry)

    let result = router.checkForContextLoading(transcript: "write phasing")

    assert(result == nil, "Should not propose context loading for write command")

    print("✅ testRouterWithRegistry_NonQuestionIgnored passed")
}

func testRouterWithRegistry_NoMatch() {
    let registry = ArtifactRegistry()

    let phasing = Artifact(
        path: "artifacts/phasing.md",
        keywords: ["phasing", "phases"],
        summary: "Project phasing plan"
    )
    registry.add(phasing)

    let router = SimpleRouter(registry: registry)

    let result = router.checkForContextLoading(transcript: "how many users")

    assert(result == nil, "Should not propose context loading when no artifact matches")

    print("✅ testRouterWithRegistry_NoMatch passed")
}

func testRouterWithRegistry_MultipleMatches() {
    let registry = ArtifactRegistry()

    let phasing = Artifact(
        path: "artifacts/phasing.md",
        keywords: ["phasing", "phases", "plan"],
        summary: "Project phasing plan"
    )

    let description = Artifact(
        path: "artifacts/description.md",
        keywords: ["description", "plan", "overview"],
        summary: "Project description"
    )

    registry.add(phasing)
    registry.add(description)

    let router = SimpleRouter(registry: registry)

    let result = router.checkForContextLoading(transcript: "what are the plan phases")

    assert(result != nil, "Should propose context loading")
    assert(result!.count <= 2, "Should limit to top 2 matches")
    assert(result!.contains("artifacts/phasing.md"), "Should include phasing artifact")

    print("✅ testRouterWithRegistry_MultipleMatches passed")
}

func testIntentParsing() {
    assert(IntentParser.parse("how many phases") == .question, "Should parse question")
    assert(IntentParser.parse("read description") == .read, "Should parse read")
    assert(IntentParser.parse("write phasing") == .write, "Should parse write")
    assert(IntentParser.parse("edit phase 3") == .edit, "Should parse edit")
    assert(IntentParser.parse("hello") == .unknown, "Should parse unknown")

    print("✅ testIntentParsing passed")
}

// MARK: - Main

print("\n=== Router Integration Tests ===\n")

testRouterWithoutRegistry()
testRouterWithRegistry_MatchesQuestion()
testRouterWithRegistry_NonQuestionIgnored()
testRouterWithRegistry_NoMatch()
testRouterWithRegistry_MultipleMatches()
testIntentParsing()

print("\n=== All Router Integration Tests Passed ✅ ===\n")
