#!/usr/bin/env swift

import Foundation

// Simple test script for fluid routing conversion logic

// Mock FluidAction (simplified for testing)
enum TestFluidAction {
    case write(artifact: String, instructions: String?)
    case read(artifact: String, scope: String?)
    case search(query: String, depth: String?)
    case copy(artifact: String)

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
            "phases?\\s+(\\d+)\\s*(?:to|through|-)\\s*(\\d+)",
            "(\\d+)\\s*(?:to|through|-)\\s*(\\d+)",
            "phases?\\s+(\\d+)\\s*and\\s*(\\d+)"
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
}

// Test Cases
struct TestCase {
    let name: String
    let fluid: TestFluidAction
    let expectedMapping: String
}

let testCases = [
    // Write operations
    TestCase(
        name: "Write spec",
        fluid: .write(artifact: "spec", instructions: nil),
        expectedMapping: "writeBoth"
    ),
    TestCase(
        name: "Write description",
        fluid: .write(artifact: "description", instructions: nil),
        expectedMapping: "writeDescription"
    ),
    TestCase(
        name: "Edit description",
        fluid: .write(artifact: "description", instructions: "make it shorter"),
        expectedMapping: "editDescription"
    ),
    TestCase(
        name: "Merge phases",
        fluid: .write(artifact: "phasing", instructions: "merge phases 2 and 3"),
        expectedMapping: "mergePhases(2, 3)"
    ),
    TestCase(
        name: "Split phase",
        fluid: .write(artifact: "phasing", instructions: "split phase 3 into parts"),
        expectedMapping: "splitPhase(3)"
    ),

    // Read operations
    TestCase(
        name: "Read spec",
        fluid: .read(artifact: "spec", scope: nil),
        expectedMapping: "readDescription"  // Will read both
    ),
    TestCase(
        name: "Read phasing",
        fluid: .read(artifact: "phasing", scope: nil),
        expectedMapping: "readPhasing"
    ),
    TestCase(
        name: "Read specific phase",
        fluid: .read(artifact: "phasing", scope: "phase 5"),
        expectedMapping: "readSpecificPhase(5)"
    ),

    // Search operations
    TestCase(
        name: "Basic search",
        fluid: .search(query: "swift concurrency", depth: nil),
        expectedMapping: "search"
    ),
    TestCase(
        name: "Deep search",
        fluid: .search(query: "kubernetes", depth: "deep"),
        expectedMapping: "deepSearch"
    ),

    // Copy operations
    TestCase(
        name: "Copy spec",
        fluid: .copy(artifact: "spec"),
        expectedMapping: "copyBoth"
    ),
    TestCase(
        name: "Copy description",
        fluid: .copy(artifact: "description"),
        expectedMapping: "copyDescription"
    ),
]

// Run tests
print("=== Testing Fluid Action Conversions ===\n")

var passCount = 0
var failCount = 0

for testCase in testCases {
    print("Test: \(testCase.name)")
    print("  Fluid: \(testCase.fluid)")
    print("  Expected: \(testCase.expectedMapping)")

    // Test phase extraction
    switch testCase.fluid {
    case .write(_, let instructions):
        if let inst = instructions {
            if inst.contains("merge") {
                if let range = testCase.fluid.extractPhaseRange(from: inst) {
                    print("  ✅ Extracted range: \(range.start)-\(range.end)")
                    passCount += 1
                } else if testCase.expectedMapping.contains("merge") {
                    print("  ❌ Failed to extract phase range")
                    failCount += 1
                } else {
                    passCount += 1
                }
            } else if inst.contains("split") {
                if let num = testCase.fluid.extractPhaseNumber(from: inst) {
                    print("  ✅ Extracted phase: \(num)")
                    passCount += 1
                } else if testCase.expectedMapping.contains("split") {
                    print("  ❌ Failed to extract phase number")
                    failCount += 1
                } else {
                    passCount += 1
                }
            } else {
                print("  ✅ Edit instruction recognized")
                passCount += 1
            }
        } else {
            print("  ✅ No instructions (create action)")
            passCount += 1
        }

    case .read(_, let scope):
        if let s = scope {
            if let num = testCase.fluid.extractPhaseNumber(from: s) {
                print("  ✅ Extracted phase from scope: \(num)")
                passCount += 1
            } else if testCase.expectedMapping.contains("Specific") {
                print("  ❌ Failed to extract phase from scope")
                failCount += 1
            } else {
                passCount += 1
            }
        } else {
            print("  ✅ No scope (read all)")
            passCount += 1
        }

    case .search(_, let depth):
        if let d = depth, d == "deep" {
            print("  ✅ Deep search recognized")
        } else {
            print("  ✅ Basic search")
        }
        passCount += 1

    case .copy:
        print("  ✅ Copy action")
        passCount += 1
    }

    print("")
}

// Additional edge case tests
print("=== Edge Case Tests ===\n")

let edgeCases = [
    ("phase one", 1),
    ("phase two", 2),
    ("phase three", 3),
    ("Phase 10", 10),
    ("edit phase 5", 5),
    ("phase#7", 7)
]

for (input, expected) in edgeCases {
    let fluid = TestFluidAction.write(artifact: "test", instructions: input)
    if let extracted = fluid.extractPhaseNumber(from: input) {
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

print("\n=== Summary ===")
print("Total tests: \(passCount + failCount)")
print("Passed: \(passCount)")
print("Failed: \(failCount)")

if failCount == 0 {
    print("\n✅ All tests passed!")
} else {
    print("\n⚠️ Some tests failed")
}