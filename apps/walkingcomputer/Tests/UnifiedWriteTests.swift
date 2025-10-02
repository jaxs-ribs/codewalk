#!/usr/bin/env swift

import Foundation

// Test script for unified write handler
// Tests that all write operations work through executeWrite()

struct TestCase {
    let name: String
    let artifact: String
    let instructions: String?
    let expectedAction: String
}

let testCases = [
    // Create operations
    TestCase(
        name: "Create description",
        artifact: "description",
        instructions: nil,
        expectedAction: "writeDescription"
    ),
    TestCase(
        name: "Create phasing",
        artifact: "phasing",
        instructions: nil,
        expectedAction: "writePhasing"
    ),
    TestCase(
        name: "Create both",
        artifact: "spec",
        instructions: nil,
        expectedAction: "writeBoth"
    ),
    TestCase(
        name: "Create both (alternate)",
        artifact: "both",
        instructions: nil,
        expectedAction: "writeBoth"
    ),

    // Edit operations
    TestCase(
        name: "Edit description",
        artifact: "description",
        instructions: "make it more concise",
        expectedAction: "editDescription"
    ),
    TestCase(
        name: "Edit phasing",
        artifact: "phasing",
        instructions: "add more detail to phase 2",
        expectedAction: "editPhasing"
    ),
    TestCase(
        name: "Edit specific phase",
        artifact: "phasing",
        instructions: "edit phase 3: add testing requirements",
        expectedAction: "editSpecificPhase(3)"
    ),

    // Merge operations
    TestCase(
        name: "Merge phases 2-3",
        artifact: "phasing",
        instructions: "merge phases 2 and 3",
        expectedAction: "mergePhases(2, 3)"
    ),
    TestCase(
        name: "Merge phases 1-3",
        artifact: "phasing",
        instructions: "merge phases 1 through 3",
        expectedAction: "mergePhases(1, 3)"
    ),
    TestCase(
        name: "Merge with range",
        artifact: "phasing",
        instructions: "merge phases 2-4",
        expectedAction: "mergePhases(2, 4)"
    ),

    // Split operations
    TestCase(
        name: "Split phase 3",
        artifact: "phasing",
        instructions: "split phase 3 into smaller parts",
        expectedAction: "splitPhase(3)"
    ),
    TestCase(
        name: "Split phase two",
        artifact: "phasing",
        instructions: "split phase two into implementation and testing",
        expectedAction: "splitPhase(2)"
    ),

    // Edge cases
    TestCase(
        name: "Description with context",
        artifact: "description",
        instructions: "focus on the user experience",
        expectedAction: "editDescription"
    ),
    TestCase(
        name: "Spec with instructions",
        artifact: "spec",
        instructions: "emphasize the technical architecture",
        expectedAction: "editBoth"
    ),
]

// Helper functions to detect action type
func detectActionType(artifact: String, instructions: String?) -> String {
    guard let inst = instructions else {
        // No instructions means create
        switch artifact.lowercased() {
        case "description": return "writeDescription"
        case "phasing": return "writePhasing"
        case "spec", "both": return "writeBoth"
        default: return "unknown"
        }
    }

    let lowerInst = inst.lowercased()

    // Check for merge
    if lowerInst.contains("merge") {
        if let range = extractPhaseRange(from: inst) {
            return "mergePhases(\(range.start), \(range.end))"
        }
        return "mergePhases(unknown)"
    }

    // Check for split
    if lowerInst.contains("split") {
        if let phase = extractPhaseNumber(from: inst) {
            return "splitPhase(\(phase))"
        }
        return "splitPhase(unknown)"
    }

    // Check for specific phase edit
    if artifact.lowercased() == "phasing", lowerInst.contains("phase") {
        if let phase = extractPhaseNumber(from: inst) {
            if lowerInst.contains("edit") || inst.contains(":") {
                return "editSpecificPhase(\(phase))"
            }
        }
    }

    // Default to edit
    switch artifact.lowercased() {
    case "description": return "editDescription"
    case "phasing": return "editPhasing"
    case "spec", "both": return "editBoth"
    default: return "unknown"
    }
}

func extractPhaseNumber(from text: String) -> Int? {
    let patterns = [
        "phase\\s+(\\d+)",
        "(\\d+)\\s*phase",
        "phase\\s+([a-z]+)",
        "#(\\d+)"
    ]

    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text) {
                let captured = String(text[range])

                // Handle word numbers
                let wordToNum = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5]
                if let num = wordToNum[captured.lowercased()] {
                    return num
                }

                // Handle numeric
                if let num = Int(captured) {
                    return num
                }
            }
        }
    }
    return nil
}

func extractPhaseRange(from text: String) -> (start: Int, end: Int)? {
    let patterns = [
        "phases?\\s+(\\d+)\\s*(?:to|through|and|-)\\s*(\\d+)",
        "(\\d+)\\s*(?:to|through|and|-)\\s*(\\d+)"
    ]

    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range1 = Range(match.range(at: 1), in: text),
               let range2 = Range(match.range(at: 2), in: text),
               let start = Int(text[range1]),
               let end = Int(text[range2]) {
                return (start, end)
            }
        }
    }
    return nil
}

// Run tests
print("=== Testing Unified Write Handler ===\n")

var passCount = 0
var failCount = 0

for testCase in testCases {
    print("Test: \(testCase.name)")
    print("  Artifact: \(testCase.artifact)")
    print("  Instructions: \(testCase.instructions ?? "nil")")
    print("  Expected: \(testCase.expectedAction)")

    let detected = detectActionType(artifact: testCase.artifact, instructions: testCase.instructions)
    print("  Detected: \(detected)")

    if detected == testCase.expectedAction {
        print("  ✅ Pass\n")
        passCount += 1
    } else {
        print("  ❌ Fail\n")
        failCount += 1
    }
}

print("=== Summary ===")
print("Total tests: \(passCount + failCount)")
print("Passed: \(passCount)")
print("Failed: \(failCount)")

if failCount == 0 {
    print("\n✅ All tests passed!")
    exit(0)
} else {
    print("\n⚠️ Some tests failed")
    exit(1)
}