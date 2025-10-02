import Foundation

/// Manages conversation history as single source of truth
class ConversationContext {
    private(set) var history: [(role: String, content: String)] = []
    private let historyLimit: Int

    init(historyLimit: Int = 100) {
        self.historyLimit = historyLimit
    }

    /// Add user transcript to history
    func addUserMessage(_ content: String) {
        history.append((role: "user", content: content))
        trimIfNeeded()
    }

    /// Add assistant response to history
    func addAssistantMessage(_ content: String) {
        history.append((role: "assistant", content: content))
        trimIfNeeded()
    }

    /// Get recent messages formatted as strings
    func recentMessages(limit: Int = 6) -> [String] {
        let slice = history.suffix(limit)
        return slice.map { entry in
            "\(entry.role.capitalized): \(entry.content)"
        }
    }

    /// Get all history
    func allMessages() -> [(role: String, content: String)] {
        return history
    }

    /// Clear all history
    func clear() {
        history.removeAll()
    }

    private func trimIfNeeded() {
        if history.count > historyLimit {
            history = Array(history.suffix(historyLimit))
        }
    }
}
