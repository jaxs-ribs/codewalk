import Foundation

/// Mirrors sessions to project artifacts folder for easy debugging (simulator only)
class DebugSessionSync {
    private let fileManager = FileManager.default
    private let projectRoot: URL?
    private let isEnabled: Bool

    init() {
        // Detect if we're in simulator/debug mode and can access project folder
        self.projectRoot = DebugSessionSync.resolveProjectRoot()
        self.isEnabled = projectRoot != nil

        if isEnabled {
            log("🔄 Debug sync enabled - mirroring to \(projectRoot!.path)", category: .system, component: "DebugSessionSync")
        } else {
            log("📱 Running on device - debug sync disabled", category: .system, component: "DebugSessionSync")
        }
    }

    private static func resolveProjectRoot() -> URL? {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment

        // Explicit override via environment variable
        if let overridePath = env["WALKINGCOMPUTER_ARTIFACTS_PATH"], !overridePath.isEmpty {
            let url = URL(fileURLWithPath: overridePath, isDirectory: true)
            return url
        }

        // Prefer Xcode PROJECT_DIR or SRCROOT when available (e.g., during builds)
        if let projectDir = env["PROJECT_DIR"], !projectDir.isEmpty {
            let url = URL(fileURLWithPath: projectDir, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        if let srcRoot = env["SRCROOT"], !srcRoot.isEmpty {
            let url = URL(fileURLWithPath: srcRoot, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        // Simulator host home gives us the host user's directory
        if let hostHome = env["SIMULATOR_HOST_HOME"], !hostHome.isEmpty {
            let candidate = URL(fileURLWithPath: hostHome, isDirectory: true)
                .appendingPathComponent("Documents")
                .appendingPathComponent("codewalk")
                .appendingPathComponent("apps")
                .appendingPathComponent("walkingcomputer")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        // Hardcoded path for simulator development
        let legacyPath = URL(fileURLWithPath: "/Users/fresh/Documents/codewalk/apps/walkingcomputer", isDirectory: true)
        if fileManager.fileExists(atPath: legacyPath.path) {
            return legacyPath
        }

        // Not in simulator or can't access project folder
        return nil
    }

    // MARK: - Sync Operations

    /// Sync session metadata to project folder
    func syncSessionMetadata(_ session: Session, from sourceURL: URL) {
        guard isEnabled, let projectRoot = projectRoot else { return }

        let debugPath = getDebugSessionPath(for: session.id)
        let targetURL = debugPath.appendingPathComponent("session.json")

        copyFile(from: sourceURL, to: targetURL)
    }

    /// Sync conversation file to project folder
    func syncConversation(for sessionId: UUID, from sourceURL: URL) {
        guard isEnabled, let projectRoot = projectRoot else { return }

        let debugPath = getDebugSessionPath(for: sessionId)
        let targetURL = debugPath.appendingPathComponent("conversation.json")

        copyFile(from: sourceURL, to: targetURL)
    }

    /// Sync artifact file to project folder
    func syncArtifact(filename: String, for sessionId: UUID, from sourceURL: URL) {
        guard isEnabled, let projectRoot = projectRoot else { return }

        let debugPath = getDebugSessionPath(for: sessionId)
        let artifactsPath = debugPath.appendingPathComponent("artifacts")
        let targetURL = artifactsPath.appendingPathComponent(filename)

        // Ensure artifacts directory exists
        try? fileManager.createDirectory(at: artifactsPath, withIntermediateDirectories: true)

        copyFile(from: sourceURL, to: targetURL)
    }

    /// Sync entire session directory to project folder
    func syncFullSession(for sessionId: UUID, from sourceDir: URL) {
        guard isEnabled, let projectRoot = projectRoot else { return }

        let debugPath = getDebugSessionPath(for: sessionId)

        // Remove existing debug session if it exists
        if fileManager.fileExists(atPath: debugPath.path) {
            try? fileManager.removeItem(at: debugPath)
        }

        // Copy entire session directory
        do {
            try fileManager.copyItem(at: sourceDir, to: debugPath)
            log("✅ Synced full session \(sessionId) to debug folder", category: .system, component: "DebugSessionSync")
        } catch {
            logError("Failed to sync session \(sessionId): \(error)", component: "DebugSessionSync")
        }
    }

    // MARK: - Helper Methods

    private func getDebugSessionPath(for sessionId: UUID) -> URL {
        let debugSessionsRoot = projectRoot!.appendingPathComponent("artifacts").appendingPathComponent("debug-sessions")
        return debugSessionsRoot.appendingPathComponent(sessionId.uuidString)
    }

    private func copyFile(from source: URL, to destination: URL) {
        do {
            // Create parent directory if needed
            let parentDir = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            // Copy file
            try fileManager.copyItem(at: source, to: destination)

            log("📋 Synced \(destination.lastPathComponent) to debug folder", category: .system, component: "DebugSessionSync")
        } catch {
            logError("Failed to copy \(source.lastPathComponent): \(error)", component: "DebugSessionSync")
        }
    }

    /// Create a symlink in project root pointing to active session (for ultimate convenience)
    func symlinkActiveSession(_ sessionId: UUID, from sourceDir: URL) {
        guard isEnabled, let projectRoot = projectRoot else { return }

        let symlinkPath = projectRoot.appendingPathComponent("artifacts").appendingPathComponent("active-session")

        // Remove existing symlink (try both remove and unlink for different file types)
        if fileManager.fileExists(atPath: symlinkPath.path) {
            do {
                try fileManager.removeItem(at: symlinkPath)
            } catch {
                // If removal fails, try unlinking directly
                _ = unlink(symlinkPath.path)
            }
        }

        // Create new symlink
        do {
            try fileManager.createSymbolicLink(at: symlinkPath, withDestinationURL: sourceDir)
            log("🔗 Updated symlink to active session: \(sessionId)", category: .system, component: "DebugSessionSync")
        } catch let error as NSError {
            // Only log if it's not a "file exists" error
            if error.code != 17 && error.code != 516 {
                logError("Failed to create symlink: \(error)", component: "DebugSessionSync")
            }
        }
    }
}
