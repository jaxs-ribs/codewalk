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

    // MARK: - Phase Split/Merge Operations

    /// Split a phase into multiple sub-phases
    func splitPhase(_ phaseNumber: Int, instructions: String, groqApiKey: String) async -> Bool {
        guard let content = safeRead(filename: "phasing.md") else {
            logError("Cannot split phase - phasing.md not found", component: "ArtifactManager")
            return false
        }

        // Parse current phases
        let phases = PhaseParser.parsePhases(from: content)

        guard let targetPhase = phases.first(where: { $0.number == phaseNumber }) else {
            logError("Phase \(phaseNumber) not found for splitting", component: "ArtifactManager")
            return false
        }

        // Create backup before modification
        createBackup(filename: "phasing.md")

        do {
            // Split the phase using AI
            let subPhases = try await PhaseParser.splitPhase(targetPhase, instructions: instructions, groqApiKey: groqApiKey)

            // Build new phase list
            var newPhases: [Phase] = []
            var phaseCounter = 1

            for phase in phases {
                if phase.number == phaseNumber {
                    // Insert the split phases
                    for subPhase in subPhases {
                        newPhases.append(Phase(
                            number: phaseCounter,
                            title: subPhase.title,
                            description: subPhase.description,
                            definitionOfDone: subPhase.definitionOfDone
                        ))
                        phaseCounter += 1
                    }
                } else if phase.number < phaseNumber {
                    // Keep phases before the split as-is
                    newPhases.append(Phase(
                        number: phaseCounter,
                        title: phase.title,
                        description: phase.description,
                        definitionOfDone: phase.definitionOfDone
                    ))
                    phaseCounter += 1
                } else {
                    // Renumber phases after the split
                    newPhases.append(Phase(
                        number: phaseCounter,
                        title: phase.title,
                        description: phase.description,
                        definitionOfDone: phase.definitionOfDone
                    ))
                    phaseCounter += 1
                }
            }

            // Write the new phasing
            let newContent = PhaseParser.phasesToMarkdown(newPhases)
            let success = safeWrite(filename: "phasing.md", content: newContent)

            if success {
                log("Successfully split phase \(phaseNumber) into \(subPhases.count) sub-phases", category: .artifacts, component: "ArtifactManager")
            }

            return success
        } catch {
            logError("Failed to split phase: \(error)", component: "ArtifactManager")
            return false
        }
    }

    /// Merge consecutive phases into one
    func mergePhases(_ startPhase: Int, _ endPhase: Int, instructions: String?, groqApiKey: String) async -> Bool {
        guard let content = safeRead(filename: "phasing.md") else {
            logError("Cannot merge phases - phasing.md not found", component: "ArtifactManager")
            return false
        }

        // Validate consecutive phases (allow merging 2-5 phases)
        guard endPhase > startPhase else {
            logError("Invalid phase range: end phase (\(endPhase)) must be greater than start phase (\(startPhase))", component: "ArtifactManager")
            return false
        }

        let phaseCount = endPhase - startPhase + 1
        guard phaseCount <= 5 else {
            logError("Cannot merge \(phaseCount) phases. Maximum is 5 phases at once. Try merging phases \(startPhase)-\(startPhase + 4) first.", component: "ArtifactManager")
            return false
        }

        // Parse current phases
        let phases = PhaseParser.parsePhases(from: content)

        // Get phases to merge
        let phasesToMerge = phases.filter { $0.number >= startPhase && $0.number <= endPhase }

        guard phasesToMerge.count == (endPhase - startPhase + 1) else {
            logError("Not all phases from \(startPhase) to \(endPhase) exist", component: "ArtifactManager")
            return false
        }

        // Create backup before modification
        createBackup(filename: "phasing.md")

        do {
            // Merge the phases using AI
            let mergedPhase = try await PhaseParser.mergePhases(phasesToMerge, instructions: instructions, groqApiKey: groqApiKey)

            // Build new phase list
            var newPhases: [Phase] = []
            var phaseCounter = 1

            for phase in phases {
                if phase.number < startPhase {
                    // Keep phases before the merge
                    newPhases.append(Phase(
                        number: phaseCounter,
                        title: phase.title,
                        description: phase.description,
                        definitionOfDone: phase.definitionOfDone
                    ))
                    phaseCounter += 1
                } else if phase.number == startPhase {
                    // Insert the merged phase
                    newPhases.append(Phase(
                        number: phaseCounter,
                        title: mergedPhase.title,
                        description: mergedPhase.description,
                        definitionOfDone: mergedPhase.definitionOfDone
                    ))
                    phaseCounter += 1
                } else if phase.number > endPhase {
                    // Renumber phases after the merge
                    newPhases.append(Phase(
                        number: phaseCounter,
                        title: phase.title,
                        description: phase.description,
                        definitionOfDone: phase.definitionOfDone
                    ))
                    phaseCounter += 1
                }
                // Skip phases between start and end (they're being merged)
            }

            // Write the new phasing
            let newContent = PhaseParser.phasesToMarkdown(newPhases)
            let success = safeWrite(filename: "phasing.md", content: newContent)

            if success {
                log("Successfully merged phases \(startPhase)-\(endPhase) into phase \(startPhase)", category: .artifacts, component: "ArtifactManager")
            }

            return success
        } catch {
            logError("Failed to merge phases: \(error)", component: "ArtifactManager")
            return false
        }
    }

    /// Edit a specific phase using diff-based approach
    func editSpecificPhase(_ phaseNumber: Int, instructions: String, groqApiKey: String) async -> Bool {
        guard let content = safeRead(filename: "phasing.md") else {
            logError("Cannot edit phase - phasing.md not found", component: "ArtifactManager")
            return false
        }

        // Parse current phases
        let phases = PhaseParser.parsePhases(from: content)

        guard let targetPhaseIndex = phases.firstIndex(where: { $0.number == phaseNumber }) else {
            logError("Phase \(phaseNumber) not found for editing", component: "ArtifactManager")
            return false
        }

        let targetPhase = phases[targetPhaseIndex]

        // Create backup before modification
        createBackup(filename: "phasing.md")

        // Use AI to edit the specific phase
        let prompt = """
        Edit this phase based on the instructions.

        Current Phase:
        Title: \(targetPhase.title)
        Description: \(targetPhase.description)
        Definition of Done: \(targetPhase.definitionOfDone)

        Instructions: \(instructions)

        Generate an updated phase with the changes. Return JSON with: title, description, definitionOfDone
        """

        let apiURL = "https://api.groq.com/openai/v1/chat/completions"

        let requestBody: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "system", "content": "You are a project planning assistant. Generate clear, updated phase content in JSON format."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3
        ]

        let headers = [
            "Authorization": "Bearer \(groqApiKey)",
            "Content-Type": "application/json"
        ]

        do {
            let response = try await NetworkManager.shared.post(url: apiURL, body: requestBody, headers: headers)

            // Parse response
            if let choices = response["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {

                // Log raw AI response for debugging
                log("Edit phase AI response: \(content)", category: .artifacts, component: "ArtifactManager")

                if let data = content.data(using: String.Encoding.utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    let title = json["title"] as? String
                    let description = json["description"] as? String

                    // Handle DoD that might be a string, array, or object (same as in merge)
                    var dod: String?
                    if let dodString = json["definitionOfDone"] as? String {
                        dod = dodString
                    } else if let dodArray = json["definitionOfDone"] as? [String] {
                        dod = dodArray.joined(separator: ". ")
                    } else if let dodObject = json["definitionOfDone"] as? [String: Any] {
                        if let criteria = dodObject["criteria"] as? [String] {
                            dod = criteria.joined(separator: ". ")
                        } else if let criteriaString = dodObject["criteria"] as? String {
                            dod = criteriaString
                        } else {
                            let values = dodObject.values.compactMap { $0 as? String }
                            if !values.isEmpty {
                                dod = values.joined(separator: ". ")
                            }
                        }
                    }

                    if let title = title,
                       let description = description,
                       let dod = dod {

                        // Create updated phase
                        let updatedPhase = Phase(
                            number: targetPhase.number,
                            title: title,
                            description: description,
                            definitionOfDone: dod
                        )

                        // Replace the phase in the array
                        var newPhases = phases
                        newPhases[targetPhaseIndex] = updatedPhase

                        // Write the updated phasing
                        let newContent = PhaseParser.phasesToMarkdown(newPhases)
                        let success = safeWrite(filename: "phasing.md", content: newContent)

                        if success {
                            log("Successfully edited phase \(phaseNumber)", category: .artifacts, component: "ArtifactManager")
                        }

                        return success
                    } else {
                        logError("Missing fields in edit response. Title: \(title ?? "nil"), Description: \(description ?? "nil"), DoD: \(dod ?? "nil")", component: "ArtifactManager")
                    }
                } else {
                    logError("Failed to parse JSON from edit response", component: "ArtifactManager")
                }
            } else {
                logError("Failed to get AI response content", component: "ArtifactManager")
            }
            return false

        } catch {
            logError("Failed to edit phase: \(error)", component: "ArtifactManager")
            return false
        }
    }
}
