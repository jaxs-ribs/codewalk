import Foundation

/// Represents a user session with its own artifacts and conversation history
struct Session: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var lastUpdated: Date

    init(id: UUID = UUID(), createdAt: Date = Date(), lastUpdated: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }

    // MARK: - Path Accessors

    /// Returns the session's root directory path
    func sessionPath(in baseURL: URL) -> URL {
        return baseURL
            .appendingPathComponent("sessions")
            .appendingPathComponent(id.uuidString)
    }

    /// Returns the session metadata file path
    func metadataPath(in baseURL: URL) -> URL {
        return sessionPath(in: baseURL).appendingPathComponent("session.json")
    }

    /// Returns the conversation history file path
    func conversationPath(in baseURL: URL) -> URL {
        return sessionPath(in: baseURL).appendingPathComponent("conversation.json")
    }

    /// Returns the artifacts directory path
    func artifactsPath(in baseURL: URL) -> URL {
        return sessionPath(in: baseURL).appendingPathComponent("artifacts")
    }

    // MARK: - Equatable

    static func == (lhs: Session, rhs: Session) -> Bool {
        return lhs.id == rhs.id
    }
}
