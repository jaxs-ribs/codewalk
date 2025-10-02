#!/usr/bin/env swift

import Foundation

// MARK: - Copy of Artifact and ArtifactRegistry for standalone testing

struct Artifact: Codable, Equatable {
    let path: String
    let type: ArtifactType
    let keywords: [String]
    let topics: [String]
    let created: Date
    let summary: String

    enum ArtifactType: String, Codable {
        case spoken = "spoken"
        case context = "context"
    }
}

struct ArtifactRegistryData: Codable {
    var artifacts: [Artifact]
}

class ArtifactRegistry {
    private var data: ArtifactRegistryData
    private let registryURL: URL
    private let fileManager = FileManager.default

    init(artifactsPath: URL) {
        self.registryURL = artifactsPath.appendingPathComponent(".registry.json")

        if let loadedData = ArtifactRegistry.loadFromDisk(url: registryURL) {
            self.data = loadedData
        } else {
            self.data = ArtifactRegistryData(artifacts: [])
        }
    }

    func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: registryURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func loadFromDisk(url: URL) -> ArtifactRegistryData? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: url)
            let registry = try decoder.decode(ArtifactRegistryData.self, from: data)
            return registry
        } catch {
            return nil
        }
    }

    func reload() {
        if let loadedData = ArtifactRegistry.loadFromDisk(url: registryURL) {
            self.data = loadedData
        }
    }

    func add(_ artifact: Artifact) {
        data.artifacts.removeAll { $0.path == artifact.path }
        data.artifacts.append(artifact)
    }

    func remove(path: String) {
        data.artifacts.removeAll { $0.path == path }
    }

    func get(path: String) -> Artifact? {
        return data.artifacts.first { $0.path == path }
    }

    func all() -> [Artifact] {
        return data.artifacts
    }

    func count() -> Int {
        return data.artifacts.count
    }

    // MARK: - Fuzzy Matching

    func match(input: String, threshold: Double = 5.0) -> [Artifact] {
        let tokens = tokenize(input)

        let scored = data.artifacts.map { artifact in
            let score = fuzzyScore(tokens: tokens, artifact: artifact)
            return (artifact, score)
        }

        return scored
            .filter { $0.1 >= threshold }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func tokenize(_ input: String) -> [String] {
        let stopWords = Set(["a", "an", "the", "is", "are", "was", "were", "in", "on", "at", "to", "for", "of", "with", "about"])

        return input
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private func fuzzyScore(tokens: [String], artifact: Artifact) -> Double {
        var score = 0.0

        for token in tokens {
            if artifact.keywords.contains(token) {
                score += 10.0
            }
            else if artifact.keywords.contains(where: { $0.contains(token) || token.contains($0) }) {
                score += 5.0
            }

            if artifact.topics.contains(token) {
                score += 5.0
            }
            else if artifact.topics.contains(where: { $0.contains(token) || token.contains($0) }) {
                score += 2.5
            }

            if artifact.summary.lowercased().contains(token) {
                score += 1.0
            }

            if artifact.path.lowercased().contains(token) {
                score += 3.0
            }
        }

        return score
    }
}

// MARK: - Test Helpers

func createTestRegistryPath() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent("registry-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    return testDir
}

func cleanupTestRegistry(at url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Tests

func testCreateEmptyRegistry() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    assert(registry.count() == 0, "New registry should be empty")
    assert(registry.all().isEmpty, "New registry should have no artifacts")

    print("✅ testCreateEmptyRegistry passed")
}

func testAddArtifact() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let artifact = Artifact(
        path: "artifacts/description.md",
        type: .spoken,
        keywords: ["description", "pitch"],
        topics: [],
        created: Date(),
        summary: "Project description"
    )

    registry.add(artifact)

    assert(registry.count() == 1, "Registry should have 1 artifact after add")
    assert(registry.all().first?.path == "artifacts/description.md", "Artifact path should match")

    print("✅ testAddArtifact passed")
}

func testPersistence() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let artifact = Artifact(
        path: "artifacts/phasing.md",
        type: .spoken,
        keywords: ["phasing", "phases"],
        topics: [],
        created: Date(),
        summary: "Project phasing plan"
    )

    registry.add(artifact)

    let saveSuccess = registry.save()
    assert(saveSuccess, "Save should succeed")

    let registryFile = path.appendingPathComponent(".registry.json")
    assert(FileManager.default.fileExists(atPath: registryFile.path), "Registry file should exist after save")

    print("✅ testPersistence passed")
}

func testReload() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry1 = ArtifactRegistry(artifactsPath: path)
    let artifact = Artifact(
        path: "artifacts/research/test.md",
        type: .context,
        keywords: ["test", "research"],
        topics: ["testing"],
        created: Date(),
        summary: "Test research"
    )
    registry1.add(artifact)
    _ = registry1.save()

    let registry2 = ArtifactRegistry(artifactsPath: path)

    assert(registry2.count() == 1, "Loaded registry should have 1 artifact")
    assert(registry2.all().first?.path == "artifacts/research/test.md", "Loaded artifact should match")
    assert(registry2.all().first?.type == .context, "Loaded artifact type should match")
    assert(registry2.all().first?.keywords == ["test", "research"], "Loaded keywords should match")

    print("✅ testReload passed")
}

func testRemoveArtifact() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let artifact1 = Artifact(
        path: "artifacts/one.md",
        type: .spoken,
        keywords: ["one"],
        topics: [],
        created: Date(),
        summary: "First"
    )

    let artifact2 = Artifact(
        path: "artifacts/two.md",
        type: .context,
        keywords: ["two"],
        topics: [],
        created: Date(),
        summary: "Second"
    )

    registry.add(artifact1)
    registry.add(artifact2)

    assert(registry.count() == 2, "Should have 2 artifacts")

    registry.remove(path: "artifacts/one.md")

    assert(registry.count() == 1, "Should have 1 artifact after remove")
    assert(registry.all().first?.path == "artifacts/two.md", "Remaining artifact should be two.md")

    print("✅ testRemoveArtifact passed")
}

func testGetArtifact() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let artifact = Artifact(
        path: "artifacts/target.md",
        type: .spoken,
        keywords: ["target"],
        topics: [],
        created: Date(),
        summary: "Target artifact"
    )

    registry.add(artifact)

    let retrieved = registry.get(path: "artifacts/target.md")
    assert(retrieved != nil, "Should retrieve artifact by path")
    assert(retrieved?.summary == "Target artifact", "Retrieved artifact should match")

    let missing = registry.get(path: "artifacts/missing.md")
    assert(missing == nil, "Should return nil for non-existent path")

    print("✅ testGetArtifact passed")
}

func testMultipleArtifacts() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    for i in 1...3 {
        let artifact = Artifact(
            path: "artifacts/item\(i).md",
            type: .context,
            keywords: ["item\(i)"],
            topics: [],
            created: Date(),
            summary: "Item \(i)"
        )
        registry.add(artifact)
    }

    assert(registry.count() == 3, "Should have 3 artifacts")

    _ = registry.save()

    let registry2 = ArtifactRegistry(artifactsPath: path)
    assert(registry2.count() == 3, "Reloaded registry should have 3 artifacts")

    let paths = registry2.all().map { $0.path }.sorted()
    assert(paths == ["artifacts/item1.md", "artifacts/item2.md", "artifacts/item3.md"], "All artifacts should survive round-trip")

    print("✅ testMultipleArtifacts passed")
}

func testEmptyRegistryRoundTrip() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let saveSuccess = registry.save()
    assert(saveSuccess, "Empty registry should save successfully")

    let registry2 = ArtifactRegistry(artifactsPath: path)
    assert(registry2.count() == 0, "Loaded empty registry should be empty")

    print("✅ testEmptyRegistryRoundTrip passed")
}

func testMatchByKeyword() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let phasing = Artifact(
        path: "artifacts/phasing.md",
        type: .spoken,
        keywords: ["phasing", "phases", "plan"],
        topics: [],
        created: Date(),
        summary: "Project phasing plan"
    )

    let description = Artifact(
        path: "artifacts/description.md",
        type: .spoken,
        keywords: ["description", "pitch", "overview"],
        topics: [],
        created: Date(),
        summary: "Project description"
    )

    registry.add(phasing)
    registry.add(description)

    let results = registry.match(input: "how many phases")
    assert(results.count > 0, "Should find matches")
    assert(results.first?.path == "artifacts/phasing.md", "Phasing should rank highest for 'phases'")

    print("✅ testMatchByKeyword passed")
}

func testMatchByTopic() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let research = Artifact(
        path: "artifacts/research/populations.md",
        type: .context,
        keywords: ["population", "countries"],
        topics: ["demographics", "statistics"],
        created: Date(),
        summary: "Population data for 195 countries"
    )

    registry.add(research)

    let results = registry.match(input: "demographics statistics")
    assert(results.count > 0, "Should find matches by topic")
    assert(results.first?.path == "artifacts/research/populations.md", "Should match research artifact")

    print("✅ testMatchByTopic passed")
}

func testMatchWithThreshold() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let artifact = Artifact(
        path: "artifacts/test.md",
        type: .context,
        keywords: ["test"],
        topics: [],
        created: Date(),
        summary: "Test artifact"
    )

    registry.add(artifact)

    let resultsLowThreshold = registry.match(input: "test", threshold: 1.0)
    assert(resultsLowThreshold.count > 0, "Should match with low threshold")

    let resultsHighThreshold = registry.match(input: "unrelated query", threshold: 10.0)
    assert(resultsHighThreshold.count == 0, "Should not match with high threshold")

    print("✅ testMatchWithThreshold passed")
}

func testMatchRanking() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let exact = Artifact(
        path: "artifacts/population.md",
        type: .context,
        keywords: ["population"],
        topics: [],
        created: Date(),
        summary: "Population data"
    )

    let partial = Artifact(
        path: "artifacts/demo.md",
        type: .context,
        keywords: ["demographics"],
        topics: [],
        created: Date(),
        summary: "Some population info here"
    )

    registry.add(exact)
    registry.add(partial)

    let results = registry.match(input: "population", threshold: 1.0)
    assert(results.count == 2, "Should find both artifacts")
    assert(results.first?.path == "artifacts/population.md", "Exact keyword match should rank higher")

    print("✅ testMatchRanking passed")
}

func testMatchNoResults() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    let registry = ArtifactRegistry(artifactsPath: path)

    let artifact = Artifact(
        path: "artifacts/test.md",
        type: .context,
        keywords: ["test"],
        topics: [],
        created: Date(),
        summary: "Test artifact"
    )

    registry.add(artifact)

    let results = registry.match(input: "completely unrelated query xyz")
    assert(results.count == 0, "Should return empty array for no matches")

    print("✅ testMatchNoResults passed")
}

// MARK: - Main

print("\n=== Artifact Registry Tests ===\n")

testCreateEmptyRegistry()
testAddArtifact()
testPersistence()
testReload()
testRemoveArtifact()
testGetArtifact()
testMultipleArtifacts()
testEmptyRegistryRoundTrip()

print("\n=== Fuzzy Matching Tests ===\n")

testMatchByKeyword()
testMatchByTopic()
testMatchWithThreshold()
testMatchRanking()
testMatchNoResults()

print("\n=== All Artifact Registry Tests Passed ✅ ===\n")
