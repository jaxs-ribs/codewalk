import Foundation

// MARK: - Artifact Manager

class ArtifactManager {
    private let artifactsPath: URL
    private let backupsPath: URL
    private let fileManager = FileManager.default

    init() {
        // Resolve host-accessible project path
        let projectRoot = ArtifactManager.resolveProjectRoot()
        artifactsPath = projectRoot.appendingPathComponent("artifacts")
        backupsPath = artifactsPath.appendingPathComponent("backups")

        // Create directories
        createDirectories()

        log("Initialized", category: .artifacts, component: "ArtifactManager")
        log("Artifacts: \(artifactsPath.path)", category: .artifacts, component: "ArtifactManager")
        log("Backups: \(backupsPath.path)", category: .artifacts, component: "ArtifactManager")
    }

    private static func resolveProjectRoot() -> URL {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment

        // Explicit override via environment variable
        if let overridePath = env["WALKINGCOMPUTER_ARTIFACTS_PATH"], !overridePath.isEmpty {
            let url = URL(fileURLWithPath: overridePath, isDirectory: true)
            log("Using artifacts override path", category: .artifacts, component: "ArtifactManager")
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

        // Fallback to previous hardcoded path for backwards compatibility
        let legacyPath = URL(fileURLWithPath: "/Users/fresh/Documents/codewalk/apps/walkingcomputer", isDirectory: true)
        if fileManager.fileExists(atPath: legacyPath.path) {
            return legacyPath
        }

        // Final fallback to the application's documents directory to avoid failing
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        logError("Falling back to app documents directory for artifacts", component: "ArtifactManager")
        return documents
    }

    private func createDirectories() {
        do {
            try fileManager.createDirectory(at: artifactsPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: backupsPath, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create directories: \(error)", component: "ArtifactManager")
        }
    }

    // MARK: - Safe Read

    func safeRead(filename: String) -> String? {
        let url = artifactsPath.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: url.path) else {
            log("File not found: \(filename)", category: .artifacts, component: "ArtifactManager")
            return nil
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            log("Successfully read \(filename) (\(content.count) chars)", category: .artifacts, component: "ArtifactManager")

            // Log preview of content
            let preview = content.prefix(200).replacingOccurrences(of: "\n", with: " ")
            log("Content preview: \(preview)...", category: .artifacts, component: "ArtifactManager")

            return content
        } catch {
            logError("Failed to read \(filename): \(error)", component: "ArtifactManager")
            return nil
        }
    }

    // MARK: - Safe Write (Atomic)

    func safeWrite(filename: String, content: String) -> Bool {
        let url = artifactsPath.appendingPathComponent(filename)
        let tempURL = url.appendingPathExtension("tmp")

        // Create backup if file exists
        if fileManager.fileExists(atPath: url.path) {
            createBackup(filename: filename)
        }

        do {
            // Write to temp file first
            try content.write(to: tempURL, atomically: false, encoding: .utf8)

            // Atomic move to final location
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }

            log("Successfully wrote \(filename) (\(content.count) chars)", category: .artifacts, component: "ArtifactManager")

            // Log preview of what was written
            let preview = content.prefix(200).replacingOccurrences(of: "\n", with: " ")
            log("Wrote content: \(preview)...", category: .artifacts, component: "ArtifactManager")

            return true
        } catch {
            logError("Failed to write \(filename): \(error)", component: "ArtifactManager")

            // Cleanup temp file if it exists
            try? fileManager.removeItem(at: tempURL)
            return false
        }
    }

    // MARK: - Backup Management

    private func createBackup(filename: String) {
        let sourceURL = artifactsPath.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        // Create timestamped backup filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        let backupFilename = "\(filename).\(timestamp).backup"
        let backupURL = backupsPath.appendingPathComponent(backupFilename)

        do {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
            log("Created backup: \(backupFilename)", category: .artifacts, component: "ArtifactManager")

            // Keep only last 10 backups per file
            cleanupOldBackups(for: filename)
        } catch {
            logError("Failed to create backup: \(error)", component: "ArtifactManager")
        }
    }

    private func cleanupOldBackups(for filename: String) {
        do {
            let backups = try fileManager.contentsOfDirectory(at: backupsPath,
                                                             includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.lastPathComponent.hasPrefix("\(filename).") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2  // Newest first
                }

            // Remove old backups beyond the 10 most recent
            if backups.count > 10 {
                for backup in backups.dropFirst(10) {
                    try fileManager.removeItem(at: backup)
                    log("Deleted old backup: \(backup.lastPathComponent)", category: .artifacts, component: "ArtifactManager")
                }
            }
        } catch {
            logError("Failed to cleanup backups: \(error)", component: "ArtifactManager")
        }
    }


    // MARK: - Phase-Specific Operations

    func readPhase(from filename: String, phaseNumber: Int) -> String? {
        guard let content = safeRead(filename: filename) else {
            logError("Cannot read phase from non-existent file: \(filename)", component: "ArtifactManager")
            return nil
        }

        // Parse phases
        let lines = content.components(separatedBy: .newlines)
        var inTargetPhase = false
        var phaseCount = 0
        var phaseContent: [String] = []

        for line in lines {
            if line.hasPrefix("## Phase") {
                phaseCount += 1

                if phaseCount == phaseNumber {
                    inTargetPhase = true
                    phaseContent.append(line)
                    continue
                } else if inTargetPhase {
                    // We've hit the next phase, stop collecting
                    break
                }
            }

            if inTargetPhase {
                phaseContent.append(line)
            }
        }

        if phaseContent.isEmpty {
            logError("Phase \(phaseNumber) not found", component: "ArtifactManager")
            return nil
        }

        let result = phaseContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        log("Read phase \(phaseNumber) (\(result.count) chars)", category: .artifacts, component: "ArtifactManager")
        return result
    }


    // MARK: - File Listing

    func listArtifacts() -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: artifactsPath.path)
                .filter { $0.hasSuffix(".md") }
                .sorted()
        } catch {
            logError("Failed to list artifacts: \(error)", component: "ArtifactManager")
            return []
        }
    }

    func fileExists(_ filename: String) -> Bool {
        let url = artifactsPath.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Path Access

    func getFullPath(for filename: String) -> URL {
        return artifactsPath.appendingPathComponent(filename)
    }
}
