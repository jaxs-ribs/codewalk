import Foundation

// MARK: - Search Depth

public enum SearchDepth: String {
    case small
    case medium

    public var model: String {
        switch self {
        case .small:
            return "sonar"
        case .medium:
            return "sonar-reasoning"
        }
    }

    public var searchContextSize: String {
        switch self {
        case .small:
            return "low"
        case .medium:
            return "medium"
        }
    }

    public var maxOutputTokens: Int {
        switch self {
        case .small:
            return 150  // ~2-3 sentences
        case .medium:
            return 250  // ~4-5 sentences
        }
    }
}