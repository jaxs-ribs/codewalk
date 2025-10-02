import Foundation

// MARK: - Test Runner

func runArtifactRegistryTests() {
    print("\n=== Artifact Registry Tests ===\n")

    testCreateEmptyRegistry()
    testAddArtifact()
    testPersistence()
    testReload()
    testRemoveArtifact()
    testGetArtifact()
    testMultipleArtifacts()
    testEmptyRegistryRoundTrip()

    print("\n=== All Artifact Registry Tests Passed ===\n")
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

// MARK: - Test Cases

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

    // Check file exists
    let registryFile = path.appendingPathComponent(".registry.json")
    assert(FileManager.default.fileExists(atPath: registryFile.path), "Registry file should exist after save")

    print("✅ testPersistence passed")
}

func testReload() {
    let path = createTestRegistryPath()
    defer { cleanupTestRegistry(at: path) }

    // Create registry, add artifact, save
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

    // Create new registry instance, should load from disk
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

    // Reload in new instance
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
