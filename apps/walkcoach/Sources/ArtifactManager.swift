import Foundation

// MARK: - Artifact Manager

class ArtifactManager {
    private let artifactsPath: URL
    private let backupsPath: URL
    private let fileManager = FileManager.default

    init() {
        // Setup paths
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        artifactsPath = documentsPath.appendingPathComponent("artifacts")
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

    // MARK: - Edit Operations

    func appendToFile(filename: String, content: String) -> Bool {
        if let existing = safeRead(filename: filename) {
            return safeWrite(filename: filename, content: existing + "\n\n" + content)
        } else {
            return safeWrite(filename: filename, content: content)
        }
    }

    func replaceInFile(filename: String, searchText: String, replacement: String) -> Bool {
        guard let existing = safeRead(filename: filename) else {
            print("[ArtifactManager] Cannot replace in non-existent file: \(filename)")
            return false
        }

        let updated = existing.replacingOccurrences(of: searchText, with: replacement)

        if updated == existing {
            print("[ArtifactManager] No changes made - search text not found")
            return false
        }

        return safeWrite(filename: filename, content: updated)
    }

    // MARK: - Phase-Specific Editing

    func editPhase(in filename: String, phaseNumber: Int, newContent: String) -> Bool {
        guard let existing = safeRead(filename: filename) else {
            print("[ArtifactManager] Cannot edit phase in non-existent file: \(filename)")
            return false
        }

        // Parse phases
        let lines = existing.components(separatedBy: .newlines)
        var inTargetPhase = false
        var phaseCount = 0
        var result: [String] = []
        var foundPhase = false

        for line in lines {
            if line.hasPrefix("## Phase") {
                phaseCount += 1
                inTargetPhase = (phaseCount == phaseNumber)

                if inTargetPhase {
                    foundPhase = true
                    // Keep the phase header
                    result.append(line)
                    // Add new content
                    result.append(newContent)
                    continue
                }
            } else if inTargetPhase && line.hasPrefix("##") {
                // End of target phase
                inTargetPhase = false
            }

            if !inTargetPhase {
                result.append(line)
            }
        }

        if !foundPhase {
            print("[ArtifactManager] Phase \(phaseNumber) not found")
            return false
        }

        return safeWrite(filename: filename, content: result.joined(separator: "\n"))
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