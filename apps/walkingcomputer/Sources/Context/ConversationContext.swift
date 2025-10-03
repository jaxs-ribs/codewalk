import Foundation

// MARK: - Message Model

/// Represents a single conversation message
struct ConversationMessage: Codable {
    let role: String
    let content: String
    let timestamp: Date

    init(role: String, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Conversation Context

/// Manages conversation history as single source of truth
class ConversationContext {
    private(set) var history: [(role: String, content: String)] = []
    private let historyLimit: Int
    private(set) var lastUpdated: Date = Date()

    init(historyLimit: Int = 100) {
        self.historyLimit = historyLimit
    }

    /// Add user transcript to history
    func addUserMessage(_ content: String) {
        history.append((role: "user", content: content))
        lastUpdated = Date()
        trimIfNeeded()
    }

    /// Add assistant response to history
    func addAssistantMessage(_ content: String) {
        history.append((role: "assistant", content: content))
        lastUpdated = Date()
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

    // MARK: - Persistence

    /// Save conversation history to file
    func saveToFile(url: URL) throws {
        let messages = history.map { ConversationMessage(role: $0.role, content: $0.content) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(messages)
        try data.write(to: url, options: .atomic)

        log("Saved \(messages.count) messages to \(url.lastPathComponent)", category: .system, component: "ConversationContext")
    }

    /// Load conversation history from file
    func loadFromFile(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            log("No conversation file found at \(url.path)", category: .system, component: "ConversationContext")
            return
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let messages = try decoder.decode([ConversationMessage].self, from: data)
        history = messages.map { ($0.role, $0.content) }

        if let lastMessage = messages.last {
            lastUpdated = lastMessage.timestamp
        }

        log("Loaded \(messages.count) messages from \(url.lastPathComponent)", category: .system, component: "ConversationContext")
    }
}
