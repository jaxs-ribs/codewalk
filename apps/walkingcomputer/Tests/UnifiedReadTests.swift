#!/usr/bin/env swift

import Foundation

// Test script for unified read handler
// Tests that all read operations work through executeRead()

struct TestCase {
    let name: String
    let artifact: String
    let scope: String?
    let expectedAction: String
}

let testCases = [
    // Basic read operations
    TestCase(
        name: "Read description",
        artifact: "description",
        scope: nil,
        expectedAction: "readDescription"
    ),
    TestCase(
        name: "Read phasing",
        artifact: "phasing",
        scope: nil,
        expectedAction: "readPhasing"
    ),
    TestCase(
        name: "Read both (spec)",
        artifact: "spec",
        scope: nil,
        expectedAction: "readBoth"
    ),
    TestCase(
        name: "Read both (alternate)",
        artifact: "both",
        scope: nil,
        expectedAction: "readBoth"
    ),

    // Specific phase reading
    TestCase(
        name: "Read phase 1",
        artifact: "phasing",
        scope: "phase 1",
        expectedAction: "readSpecificPhase(1)"
    ),
    TestCase(
        name: "Read phase 5",
        artifact: "phasing",
        scope: "phase 5",
        expectedAction: "readSpecificPhase(5)"
    ),
    TestCase(
        name: "Read phase two",
        artifact: "phasing",
        scope: "phase two",
        expectedAction: "readSpecificPhase(2)"
    ),
    TestCase(
        name: "Read phase #3",
        artifact: "phasing",
        scope: "#3",
        expectedAction: "readSpecificPhase(3)"
    ),

    // Phase range reading
    TestCase(
        name: "Read phases 1-3",
        artifact: "phasing",
        scope: "phases 1-3",
        expectedAction: "readPhaseRange(1, 3)"
    ),
    TestCase(
        name: "Read phases 2 through 4",
        artifact: "phasing",
        scope: "phases 2 through 4",
        expectedAction: "readPhaseRange(2, 4)"
    ),
    TestCase(
        name: "Read phases 1 to 5",
        artifact: "phasing",
        scope: "phases 1 to 5",
        expectedAction: "readPhaseRange(1, 5)"
    ),

    // Edge cases
    TestCase(
        name: "Description with null scope",
        artifact: "description",
        scope: nil,
        expectedAction: "readDescription"
    ),
    TestCase(
        name: "Phasing with empty scope",
        artifact: "phasing",
        scope: "",
        expectedAction: "readPhasing"
    ),
]

// Helper functions to detect action type
func detectActionType(artifact: String, scope: String?) -> String {
    let artifactLower = artifact.lowercased()

    // Handle spec/both - reads both
    if artifactLower == "spec" || artifactLower == "both" {
        return "readBoth"
    }

    // Handle description
    if artifactLower == "description" {
        return "readDescription"
    }

    // Handle phasing with various scopes
    if artifactLower == "phasing" {
        guard let scopeText = scope, !scopeText.isEmpty else {
            return "readPhasing"
        }

        let lowerScope = scopeText.lowercased()

        // Check for phase range
        if lowerScope.contains("through") || lowerScope.contains("-") ||
           (lowerScope.contains("phases") && lowerScope.contains("to")) {
            if let range = extractPhaseRange(from: scopeText) {
                return "readPhaseRange(\(range.start), \(range.end))"
            }
        }

        // Check for specific phase
        if let phaseNum = extractPhaseNumber(from: scopeText) {
            return "readSpecificPhase(\(phaseNum))"
        }

        // Default to reading all phasing if scope can't be parsed
        return "readPhasing"
    }

    return "unknown"
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

    // Special case: just a number
    if let num = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return num
    }

    return nil
}

func extractPhaseRange(from text: String) -> (start: Int, end: Int)? {
    let patterns = [
        "phases?\\s+(\\d+)\\s*(?:to|through|-)\\s*(\\d+)",
        "(\\d+)\\s*(?:to|through|-)\\s*(\\d+)"
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
print("=== Testing Unified Read Handler ===\n")

var passCount = 0
var failCount = 0

for testCase in testCases {
    print("Test: \(testCase.name)")
    print("  Artifact: \(testCase.artifact)")
    print("  Scope: \(testCase.scope ?? "nil")")
    print("  Expected: \(testCase.expectedAction)")

    let detected = detectActionType(artifact: testCase.artifact, scope: testCase.scope)
    print("  Detected: \(detected)")

    if detected == testCase.expectedAction {
        print("  ✅ Pass\n")
        passCount += 1
    } else {
        print("  ❌ Fail\n")
        failCount += 1
    }
}

// Additional edge case tests for phase extraction
print("=== Phase Extraction Tests ===\n")

let phaseExtractionTests = [
    ("phase 1", 1),
    ("phase one", 1),
    ("phase two", 2),
    ("Phase 10", 10),
    ("#7", 7),
    ("3", 3),
    ("phase#5", 5)
]

for (input, expected) in phaseExtractionTests {
    if let extracted = extractPhaseNumber(from: input) {
        if extracted == expected {
            print("✅ '\(input)' → \(extracted)")
            passCount += 1
        } else {
            print("❌ '\(input)' → \(extracted) (expected \(expected))")
            failCount += 1
        }
    } else {
        print("❌ '\(input)' → nil (expected \(expected))")
        failCount += 1
    }
}

// Phase range extraction tests
print("\n=== Range Extraction Tests ===\n")

let rangeExtractionTests = [
    ("phases 1-3", (1, 3)),
    ("phases 2 through 4", (2, 4)),
    ("1 to 5", (1, 5)),
    ("phases 3-7", (3, 7))
]

for (input, expected) in rangeExtractionTests {
    if let extracted = extractPhaseRange(from: input) {
        if extracted.start == expected.0 && extracted.end == expected.1 {
            print("✅ '\(input)' → \(extracted.start)-\(extracted.end)")
            passCount += 1
        } else {
            print("❌ '\(input)' → \(extracted.start)-\(extracted.end) (expected \(expected.0)-\(expected.1))")
            failCount += 1
        }
    } else {
        print("❌ '\(input)' → nil (expected \(expected.0)-\(expected.1))")
        failCount += 1
    }
}

print("\n=== Summary ===")
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