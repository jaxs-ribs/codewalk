#!/usr/bin/env swift

import Foundation

// MARK: - Simplified types for testing

struct Artifact: Equatable {
    let path: String
    let keywords: [String]
    let summary: String
    let created: Date
}

class ArtifactRegistry {
    private var artifacts: [Artifact] = []
    private var saveCounter = 0

    func add(_ artifact: Artifact) {
        // Remove existing artifact with same path
        artifacts.removeAll { $0.path == artifact.path }
        artifacts.append(artifact)
    }

    func save() -> Bool {
        saveCounter += 1
        return true
    }

    func count() -> Int {
        return artifacts.count
    }

    func get(path: String) -> Artifact? {
        return artifacts.first { $0.path == path }
    }

    func getSaveCount() -> Int {
        return saveCounter
    }
}

class ConversationHistory {
    private var history: [String] = []

    func add(_ message: String) {
        history.append(message)
    }

    func contains(_ text: String) -> Bool {
        return history.contains { $0.contains(text) }
    }

    func count() -> Int {
        return history.count
    }
}

// Simulates the orchestrator's breadcrumb logic
func updateRegistryAfterWrite(
    registry: ArtifactRegistry,
    conversation: ConversationHistory,
    filename: String,
    content: String,
    keywords: [String]
) {
    let path = "artifacts/\(filename)"

    // Extract summary
    let summary = extractSummary(from: content)

    let artifact = Artifact(
        path: path,
        keywords: keywords,
        summary: summary,
        created: Date()
    )

    registry.add(artifact)
    _ = registry.save()

    // Add breadcrumb
    let breadcrumb = """
    [ARTIFACT: \(filename)]
    Path: \(path)
    Keywords: \(keywords.joined(separator: ", "))
    Summary: \(summary)
    """

    conversation.add(breadcrumb)
}

func extractSummary(from content: String, maxLength: Int = 200) -> String {
    let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

    if let firstLine = lines.first {
        let summary = firstLine.trimmingCharacters(in: .whitespaces)
        if summary.count <= maxLength {
            return summary
        }
        return String(summary.prefix(maxLength)) + "..."
    }

    return String(content.prefix(maxLength)) + "..."
}

// MARK: - Tests

func testUpdateRegistryOnWrite() {
    let registry = ArtifactRegistry()
    let conversation = ConversationHistory()

    let content = "# Project Description\n\nThis is a voice-first speccer."

    updateRegistryAfterWrite(
        registry: registry,
        conversation: conversation,
        filename: "description.md",
        content: content,
        keywords: ["description", "pitch"]
    )

    assert(registry.count() == 1, "Registry should have 1 artifact")
    assert(registry.getSaveCount() == 1, "Registry should be saved once")

    let artifact = registry.get(path: "artifacts/description.md")
    assert(artifact != nil, "Artifact should be in registry")
    assert(artifact?.keywords == ["description", "pitch"], "Keywords should match")
    assert(artifact?.summary.contains("Project Description") == true, "Summary should contain first line")

    print("✅ testUpdateRegistryOnWrite passed")
}

func testBreadcrumbAddedToConversation() {
    let registry = ArtifactRegistry()
    let conversation = ConversationHistory()

    let content = "# Phasing Plan\n\nPhase 1: Setup"

    updateRegistryAfterWrite(
        registry: registry,
        conversation: conversation,
        filename: "phasing.md",
        content: content,
        keywords: ["phasing", "phases"]
    )

    assert(conversation.count() == 1, "Should have 1 breadcrumb in conversation")
    assert(conversation.contains("[ARTIFACT: phasing.md]"), "Should contain artifact marker")
    assert(conversation.contains("Path: artifacts/phasing.md"), "Should contain path")
    assert(conversation.contains("Keywords: phasing, phases"), "Should contain keywords")
    assert(conversation.contains("Phasing Plan"), "Should contain summary")

    print("✅ testBreadcrumbAddedToConversation passed")
}

func testUpdateExistingArtifact() {
    let registry = ArtifactRegistry()
    let conversation = ConversationHistory()

    // First write
    updateRegistryAfterWrite(
        registry: registry,
        conversation: conversation,
        filename: "description.md",
        content: "# Original Description",
        keywords: ["description"]
    )

    assert(registry.count() == 1, "Should have 1 artifact after first write")

    // Edit (second write)
    updateRegistryAfterWrite(
        registry: registry,
        conversation: conversation,
        filename: "description.md",
        content: "# Updated Description",
        keywords: ["description", "pitch"]
    )

    assert(registry.count() == 1, "Should still have 1 artifact after edit")
    assert(registry.getSaveCount() == 2, "Registry should be saved twice")

    let artifact = registry.get(path: "artifacts/description.md")
    assert(artifact?.summary.contains("Updated") == true, "Summary should be updated")
    assert(artifact?.keywords.count == 2, "Keywords should be updated")

    assert(conversation.count() == 2, "Should have 2 breadcrumbs (write + edit)")

    print("✅ testUpdateExistingArtifact passed")
}

func testSummaryExtraction() {
    // Short content
    let short = "Brief description"
    let shortSummary = extractSummary(from: short)
    assert(shortSummary == "Brief description", "Short content should be used as-is")

    // Multi-line content
    let multiLine = "First line\nSecond line\nThird line"
    let multiLineSummary = extractSummary(from: multiLine)
    assert(multiLineSummary == "First line", "Should use first line")

    // Long content
    let longLine = String(repeating: "a", count: 250)
    let longSummary = extractSummary(from: longLine, maxLength: 200)
    assert(longSummary.count == 203, "Should truncate to 200 chars + '...'")
    assert(longSummary.hasSuffix("..."), "Should end with '...'")

    // Empty lines handling
    let withEmptyLines = "\n\nActual content\nMore content"
    let emptyLinesSummary = extractSummary(from: withEmptyLines)
    assert(emptyLinesSummary == "Actual content", "Should skip empty lines")

    print("✅ testSummaryExtraction passed")
}

func testMultipleArtifacts() {
    let registry = ArtifactRegistry()
    let conversation = ConversationHistory()

    updateRegistryAfterWrite(
        registry: registry,
        conversation: conversation,
        filename: "description.md",
        content: "Description content",
        keywords: ["description"]
    )

    updateRegistryAfterWrite(
        registry: registry,
        conversation: conversation,
        filename: "phasing.md",
        content: "Phasing content",
        keywords: ["phasing"]
    )

    assert(registry.count() == 2, "Should have 2 artifacts")
    assert(conversation.count() == 2, "Should have 2 breadcrumbs")
    assert(registry.getSaveCount() == 2, "Should save twice")

    print("✅ testMultipleArtifacts passed")
}

// MARK: - Main

print("\n=== Breadcrumb and Registry Update Tests ===\n")

testUpdateRegistryOnWrite()
testBreadcrumbAddedToConversation()
testUpdateExistingArtifact()
testSummaryExtraction()
testMultipleArtifacts()

print("\n=== All Breadcrumb Tests Passed ✅ ===\n")
