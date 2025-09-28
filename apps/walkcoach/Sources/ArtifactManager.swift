import Foundation

// MARK: - Artifact Manager

class ArtifactManager {
    private let artifactsPath: URL
    private let backupsPath: URL
    private let fileManager = FileManager.default

    init() {
        // Use the project directory for artifacts (accessible from host)
        // This allows artifacts to be visible in the repo, not hidden in simulator
        let projectPath = "/Users/fresh/Documents/codewalk/apps/walkcoach"
        artifactsPath = URL(fileURLWithPath: projectPath).appendingPathComponent("artifacts")
        backupsPath = artifactsPath.appendingPathComponent("backups")

        // Create directories
        createDirectories()

        print("[ArtifactManager] Initialized")
        print("[ArtifactManager] Artifacts: \(artifactsPath.path)")
        print("[ArtifactManager] Backups: \(backupsPath.path)")
    }

    private func createDirectories() {
        do {
            try fileManager.createDirectory(at: artifactsPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: backupsPath, withIntermediateDirectories: true)
        } catch {
            print("[ArtifactManager] Failed to create directories: \(error)")
        }
    }

    // MARK: - Safe Read

    func safeRead(filename: String) -> String? {
        let url = artifactsPath.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: url.path) else {
            print("[ArtifactManager] File not found: \(filename)")
            return nil
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            print("[ArtifactManager] Successfully read \(filename) (\(content.count) chars)")

            // Log preview of content
            let preview = content.prefix(200).replacingOccurrences(of: "\n", with: " ")
            print("[ArtifactManager] Content preview: \(preview)...")

            return content
        } catch {
            print("[ArtifactManager] Failed to read \(filename): \(error)")
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

            print("[ArtifactManager] Successfully wrote \(filename) (\(content.count) chars)")

            // Log preview of what was written
            let preview = content.prefix(200).replacingOccurrences(of: "\n", with: " ")
            print("[ArtifactManager] Wrote content: \(preview)...")

            return true
        } catch {
            print("[ArtifactManager] Failed to write \(filename): \(error)")

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
            print("[ArtifactManager] Created backup: \(backupFilename)")

            // Keep only last 10 backups per file
            cleanupOldBackups(for: filename)
        } catch {
            print("[ArtifactManager] Failed to create backup: \(error)")
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
                    print("[ArtifactManager] Deleted old backup: \(backup.lastPathComponent)")
                }
            }
        } catch {
            print("[ArtifactManager] Failed to cleanup backups: \(error)")
        }
    }


    // MARK: - Phase-Specific Operations

    func readPhase(from filename: String, phaseNumber: Int) -> String? {
        guard let content = safeRead(filename: filename) else {
            print("[ArtifactManager] Cannot read phase from non-existent file: \(filename)")
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
            print("[ArtifactManager] Phase \(phaseNumber) not found")
            return nil
        }

        let result = phaseContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ArtifactManager] Read phase \(phaseNumber) (\(result.count) chars)")
        return result
    }


    // MARK: - File Listing

    func listArtifacts() -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: artifactsPath.path)
                .filter { $0.hasSuffix(".md") }
                .sorted()
        } catch {
            print("[ArtifactManager] Failed to list artifacts: \(error)")
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