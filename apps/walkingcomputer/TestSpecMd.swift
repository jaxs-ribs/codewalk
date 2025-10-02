#!/usr/bin/env swift

import Foundation

// Test script to verify spec.md functionality

// Setup paths
let projectPath = "/Users/fresh/Documents/codewalk/apps/walkingcomputer"
let artifactsPath = "\(projectPath)/artifacts"

let fileManager = FileManager.default

// Test data
let testDescription = """
# Project Description

## What We're Building
A voice-first mobile app that helps you spec projects while walking.

## Core Features
- Voice input and output
- Real-time transcription
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

// Helper functions
func writeFile(_ filename: String, content: String) -> Bool {
    let url = URL(fileURLWithPath: artifactsPath).appendingPathComponent(filename)
    do {
        try content.write(to: url, atomically: true, encoding: .utf8)
        print("✅ Wrote \(filename)")
        return true
    } catch {
        print("❌ Failed to write \(filename): \(error)")
        return false
    }
}

func readFile(_ filename: String) -> String? {
    let url = URL(fileURLWithPath: artifactsPath).appendingPathComponent(filename)
    do {
        let content = try String(contentsOf: url, encoding: .utf8)
        print("✅ Read \(filename) (\(content.count) chars)")
        return content
    } catch {
        print("❌ Failed to read \(filename): \(error)")
        return nil
    }
}

func deleteFile(_ filename: String) {
    let url = URL(fileURLWithPath: artifactsPath).appendingPathComponent(filename)
    try? fileManager.removeItem(at: url)
    print("🗑️ Deleted \(filename)")
}

// Run tests
print("\n=== Testing spec.md Functionality ===\n")

// Test 1: Clean state
print("Test 1: Clean state")
deleteFile("spec.md")
deleteFile("description.md")
deleteFile("phasing.md")
deleteFile("description.md.legacy")
deleteFile("phasing.md.legacy")

// Test 2: Write combined spec.md
print("\nTest 2: Write combined spec.md")
let combinedContent = testDescription + "\n\n" + testPhasing
let writeSuccess = writeFile("spec.md", content: combinedContent)
assert(writeSuccess, "Failed to write spec.md")

// Test 3: Read spec.md
print("\nTest 3: Read spec.md")
if let content = readFile("spec.md") {
    assert(content.contains("Project Description"), "Missing description section")
    assert(content.contains("Project Phasing"), "Missing phasing section")
    assert(content.contains("Phase 1: Foundation"), "Missing phase content")
    print("✅ spec.md contains both sections")
}

// Test 4: Legacy migration
print("\nTest 4: Legacy migration")
deleteFile("spec.md")
_ = writeFile("description.md", content: testDescription)
_ = writeFile("phasing.md", content: testPhasing)
print("Created legacy files, app should migrate on next read")

// Test 5: Check legacy files exist
print("\nTest 5: Verify legacy files exist")
assert(fileManager.fileExists(atPath: "\(artifactsPath)/description.md"), "description.md should exist")
assert(fileManager.fileExists(atPath: "\(artifactsPath)/phasing.md"), "phasing.md should exist")
print("✅ Legacy files confirmed")

print("\n=== All Manual Tests Passed ===")
print("\nNext step: Run the app and verify it:")
print("1. Reads legacy files on first access")
print("2. Creates spec.md automatically")
print("3. Renames legacy files to .legacy")
print("4. All voice commands work with spec.md")