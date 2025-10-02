import Foundation

// MARK: - User Intent

enum UserIntent {
    case read        // "read X", "tell me X", "what does X say"
    case question    // "how many", "what are", "is there", "does"
    case write       // "write X", "create X"
    case edit        // "edit X", "change X", "update X"
    case unknown     // Fallback
}

// MARK: - Intent Parser

struct IntentParser {

    /// Parse user input to determine their intent
    static func parse(_ input: String) -> UserIntent {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Read patterns (explicit reading commands)
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

        // Question patterns (asking about artifacts)
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

        // Write patterns
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

        // Edit patterns
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

        // If no pattern matches, try to infer from question marks
        if lower.contains("?") {
            return .question
        }

        // Default to unknown
        return .unknown
    }
}
