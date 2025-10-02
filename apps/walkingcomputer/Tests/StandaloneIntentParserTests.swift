#!/usr/bin/env swift

import Foundation

// MARK: - Copy of Intent Parser for standalone testing

enum UserIntent {
    case read
    case question
    case write
    case edit
    case unknown
}

struct IntentParser {
    static func parse(_ input: String) -> UserIntent {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let readPatterns = [
            "^read ",
            "^tell me ",
            "^what does .* say",
            "^show me ",
            "^display ",
        ]

        for pattern in readPatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                return .read
            }
        }

        let questionPatterns = [
            "^how many ",
            "^what are ",
            "^what's ",
            "^is there ",
            "^are there ",
            "^does ",
            "^do ",
            "^can you tell me ",
            "^which ",
            "^when ",
            "^where ",
        ]

        for pattern in questionPatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                return .question
            }
        }

        let writePatterns = [
            "^write ",
            "^create ",
            "^generate ",
            "^make ",
        ]

        for pattern in writePatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                return .write
            }
        }

        let editPatterns = [
            "^edit ",
            "^change ",
            "^update ",
            "^modify ",
            "^fix ",
            "^revise ",
        ]

        for pattern in editPatterns {
            if let _ = lower.range(of: pattern, options: .regularExpression) {
                return .edit
            }
        }

        if lower.contains("?") {
            return .question
        }

        return .unknown
    }
}

// MARK: - Tests

func testReadIntent() {
    assert(IntentParser.parse("read description") == .read, "Should detect 'read' intent")
    assert(IntentParser.parse("tell me about the phasing") == .read, "Should detect 'tell me' as read")
    assert(IntentParser.parse("show me phase 3") == .read, "Should detect 'show me' as read")
    assert(IntentParser.parse("Read the description") == .read, "Should be case-insensitive")

    print("✅ testReadIntent passed")
}

func testQuestionIntent() {
    assert(IntentParser.parse("how many phases") == .question, "Should detect 'how many' as question")
    assert(IntentParser.parse("what are the main challenges") == .question, "Should detect 'what are' as question")
    assert(IntentParser.parse("is there a phase for testing") == .question, "Should detect 'is there' as question")
    assert(IntentParser.parse("does phase 3 include deployment") == .question, "Should detect 'does' as question")
    assert(IntentParser.parse("What's the status?") == .question, "Should detect 'what's' as question")
    assert(IntentParser.parse("How long will this take?") == .question, "Should detect 'how' as question")
    assert(IntentParser.parse("The deadline is approaching?") == .question, "Should detect '?' as question")

    print("✅ testQuestionIntent passed")
}

func testWriteIntent() {
    assert(IntentParser.parse("write description") == .write, "Should detect 'write' intent")
    assert(IntentParser.parse("create phasing") == .write, "Should detect 'create' as write")
    assert(IntentParser.parse("generate the plan") == .write, "Should detect 'generate' as write")
    assert(IntentParser.parse("make a new artifact") == .write, "Should detect 'make' as write")

    print("✅ testWriteIntent passed")
}

func testEditIntent() {
    assert(IntentParser.parse("edit phase 3") == .edit, "Should detect 'edit' intent")
    assert(IntentParser.parse("change the description") == .edit, "Should detect 'change' as edit")
    assert(IntentParser.parse("update phasing") == .edit, "Should detect 'update' as edit")
    assert(IntentParser.parse("modify phase 2") == .edit, "Should detect 'modify' as edit")
    assert(IntentParser.parse("fix the plan") == .edit, "Should detect 'fix' as edit")

    print("✅ testEditIntent passed")
}

func testUnknownIntent() {
    assert(IntentParser.parse("hello there") == .unknown, "Should return unknown for greetings")
    assert(IntentParser.parse("I think we should...") == .unknown, "Should return unknown for statements")
    assert(IntentParser.parse("") == .unknown, "Should return unknown for empty string")

    print("✅ testUnknownIntent passed")
}

func testAmbiguousInputs() {
    // These are edge cases that should still work
    assert(IntentParser.parse("read") == .unknown, "'read' alone should be unknown")
    assert(IntentParser.parse("what") == .unknown, "'what' alone should be unknown")
    assert(IntentParser.parse("edit") == .unknown, "'edit' alone should be unknown")

    print("✅ testAmbiguousInputs passed")
}

// MARK: - Main

print("\n=== Intent Parser Tests ===\n")

testReadIntent()
testQuestionIntent()
testWriteIntent()
testEditIntent()
testUnknownIntent()
testAmbiguousInputs()

print("\n=== All Intent Parser Tests Passed ✅ ===\n")
