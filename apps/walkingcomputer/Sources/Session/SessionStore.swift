import Foundation

/// Handles persistent storage of sessions
class SessionStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let debugSync: DebugSessionSync

    init() {
        // Use app's documents directory for iOS compatibility
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            baseURL = documentsURL
        } else {
            // Fallback to temp directory if documents not available
            baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            logError("Could not access documents directory, using temp", component: "SessionStore")
        }

        debugSync = DebugSessionSync()

        log("Initialized with base path: \(baseURL.path)", category: .system, component: "SessionStore")
    }

    // MARK: - Create

    /// Creates a new session with generated UUID
    func createSession() -> Session {
        let session = Session()

        // Create session directory structure
        let sessionPath = session.sessionPath(in: baseURL)
        let artifactsPath = session.artifactsPath(in: baseURL)
        let backupsPath = artifactsPath.appendingPathComponent("backups")

        do {
            try fileManager.createDirectory(at: sessionPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: artifactsPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: backupsPath, withIntermediateDirectories: true)

            // Save session metadata
            try saveMetadata(session)

            log("Created session: \(session.id)", category: .system, component: "SessionStore")
            return session
        } catch {
            logError("Failed to create session: \(error)", component: "SessionStore")
            return session
        }
    }

    // MARK: - Read

    /// Lists all sessions, sorted by lastUpdated descending
    func listSessions() -> [Session] {
        let sessionsURL = baseURL.appendingPathComponent("sessions")

        guard fileManager.fileExists(atPath: sessionsURL.path) else {
            log("No sessions directory found", category: .system, component: "SessionStore")
            return []
        }

        do {
            let sessionDirs = try fileManager.contentsOfDirectory(
                at: sessionsURL,
                includingPropertiesForKeys: nil
            ).filter { $0.hasDirectoryPath }

            var sessions: [Session] = []

            for dir in sessionDirs {
                let metadataURL = dir.appendingPathComponent("session.json")
                if let session = loadMetadata(from: metadataURL) {
                    sessions.append(session)
                }
            }

            // Sort by lastUpdated descending
            sessions.sort { $0.lastUpdated > $1.lastUpdated }

            log("Found \(sessions.count) sessions", category: .system, component: "SessionStore")
            return sessions
        } catch {
            logError("Failed to list sessions: \(error)", component: "SessionStore")
            return []
        }
    }

    /// Loads a specific session by ID
    func loadSession(id: UUID) -> Session? {
        let sessionsURL = baseURL.appendingPathComponent("sessions")
        let sessionURL = sessionsURL.appendingPathComponent(id.uuidString)
        let metadataURL = sessionURL.appendingPathComponent("session.json")

        return loadMetadata(from: metadataURL)
    }

    /// Checks if a session exists
    func sessionExists(id: UUID) -> Bool {
        let session = Session(id: id)
        let path = session.sessionPath(in: baseURL)
        return fileManager.fileExists(atPath: path.path)
    }

    // MARK: - Update

    /// Updates session's lastUpdated timestamp
    func updateLastUpdated(_ session: inout Session) {
        session.lastUpdated = Date()
        do {
            try saveMetadata(session)
            log("Updated lastUpdated for session: \(session.id)", category: .system, component: "SessionStore")
        } catch {
            logError("Failed to update session: \(error)", component: "SessionStore")
        }
    }

    // MARK: - Metadata Persistence

    private func saveMetadata(_ session: Session) throws {
        let metadataURL = session.metadataPath(in: baseURL)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(session)
        try data.write(to: metadataURL, options: .atomic)

        log("Saved metadata for session: \(session.id)", category: .system, component: "SessionStore")

        // Debug sync
        debugSync.syncSessionMetadata(session, from: metadataURL)
    }

    private func loadMetadata(from url: URL) -> Session? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let session = try decoder.decode(Session.self, from: data)
            log("Loaded metadata for session: \(session.id)", category: .system, component: "SessionStore")
            return session
        } catch {
            logError("Failed to load metadata from \(url.path): \(error)", component: "SessionStore")
            return nil
        }
    }

    // MARK: - Path Access

    /// Returns the base URL for sessions
    func getBaseURL() -> URL {
        return baseURL
    }

    /// Returns the session path for a given session ID
    func getSessionPath(for sessionId: UUID) -> URL {
        let session = Session(id: sessionId)
        return session.sessionPath(in: baseURL)
    }
}
