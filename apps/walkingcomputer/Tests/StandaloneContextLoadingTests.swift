#!/usr/bin/env swift

import Foundation

// MARK: - Simple context loading simulator for testing

class ContextLoader {
    private var loadedContext: [String: String] = [:]
    private var files: [String: String] = [:]  // Simulated file system

    // Simulate artifact manager
    func createFile(path: String, content: String) {
        files[path] = content
    }

    func loadContext(paths: [String]) {
        loadedContext.removeAll()

        for path in paths {
            if let content = files[path] {
                loadedContext[path] = content
            }
        }
    }

    func getLoadedContext() -> String {
        guard !loadedContext.isEmpty else { return "" }

        var contextString = ""
        for (path, content) in loadedContext.sorted(by: { $0.key < $1.key }) {
            contextString += "\n[Context from \(path)]:\n\(content)\n"
        }
        return contextString
    }

    func clearLoadedContext() {
        loadedContext.removeAll()
    }

    func hasLoadedContext() -> Bool {
        return !loadedContext.isEmpty
    }

    func loadedPaths() -> [String] {
        return Array(loadedContext.keys).sorted()
    }
}

// MARK: - Tests

func testLoadSingleArtifact() {
    let loader = ContextLoader()

    loader.createFile(path: "artifacts/phasing.md", content: "# Phasing\n\nPhase 1: Setup")
    loader.loadContext(paths: ["artifacts/phasing.md"])

    assert(loader.hasLoadedContext(), "Should have loaded context")
    assert(loader.loadedPaths() == ["artifacts/phasing.md"], "Should track loaded path")

    let context = loader.getLoadedContext()
    assert(context.contains("Phase 1: Setup"), "Context should contain artifact content")
    assert(context.contains("[Context from artifacts/phasing.md]"), "Context should include path marker")

    print("✅ testLoadSingleArtifact passed")
}

func testLoadMultipleArtifacts() {
    let loader = ContextLoader()

    loader.createFile(path: "artifacts/phasing.md", content: "Phase 1")
    loader.createFile(path: "artifacts/description.md", content: "Project description")

    loader.loadContext(paths: ["artifacts/phasing.md", "artifacts/description.md"])

    assert(loader.loadedPaths().count == 2, "Should have loaded 2 artifacts")

    let context = loader.getLoadedContext()
    assert(context.contains("Phase 1"), "Should contain phasing content")
    assert(context.contains("Project description"), "Should contain description content")

    print("✅ testLoadMultipleArtifacts passed")
}

func testClearContext() {
    let loader = ContextLoader()

    loader.createFile(path: "artifacts/test.md", content: "Test content")
    loader.loadContext(paths: ["artifacts/test.md"])

    assert(loader.hasLoadedContext(), "Should have context before clear")

    loader.clearLoadedContext()

    assert(!loader.hasLoadedContext(), "Should have no context after clear")
    assert(loader.getLoadedContext().isEmpty, "Context string should be empty")

    print("✅ testClearContext passed")
}

func testLoadNonExistentArtifact() {
    let loader = ContextLoader()

    loader.loadContext(paths: ["artifacts/missing.md"])

    assert(!loader.hasLoadedContext(), "Should have no context for missing file")
    assert(loader.getLoadedContext().isEmpty, "Context should be empty")

    print("✅ testLoadNonExistentArtifact passed")
}

func testLoadReplacesPreviousContext() {
    let loader = ContextLoader()

    loader.createFile(path: "artifacts/first.md", content: "First content")
    loader.createFile(path: "artifacts/second.md", content: "Second content")

    loader.loadContext(paths: ["artifacts/first.md"])
    assert(loader.loadedPaths() == ["artifacts/first.md"], "Should have first artifact")

    loader.loadContext(paths: ["artifacts/second.md"])
    assert(loader.loadedPaths() == ["artifacts/second.md"], "Should replace with second artifact")
    assert(!loader.loadedPaths().contains("artifacts/first.md"), "First artifact should be cleared")

    print("✅ testLoadReplacesPreviousContext passed")
}

func testEmptyPathsArray() {
    let loader = ContextLoader()

    loader.createFile(path: "artifacts/test.md", content: "Test")
    loader.loadContext(paths: ["artifacts/test.md"])

    assert(loader.hasLoadedContext(), "Should have context initially")

    loader.loadContext(paths: [])

    assert(!loader.hasLoadedContext(), "Should clear context with empty array")

    print("✅ testEmptyPathsArray passed")
}

func testContextFormat() {
    let loader = ContextLoader()

    loader.createFile(path: "artifacts/test.md", content: "Test content")
    loader.loadContext(paths: ["artifacts/test.md"])

    let context = loader.getLoadedContext()

    // Check format: should have markers and content
    assert(context.hasPrefix("\n"), "Should start with newline")
    assert(context.contains("[Context from artifacts/test.md]:"), "Should have path marker")
    assert(context.contains("Test content"), "Should have content")

    print("✅ testContextFormat passed")
}

// MARK: - Main

print("\n=== Context Loading Tests ===\n")

testLoadSingleArtifact()
testLoadMultipleArtifacts()
testClearContext()
testLoadNonExistentArtifact()
testLoadReplacesPreviousContext()
testEmptyPathsArray()
testContextFormat()

print("\n=== All Context Loading Tests Passed ✅ ===\n")
