import Foundation

/// Handles phase-specific operations: split, merge, edit
class PhaseEditor {
    private let store: ArtifactStore
    private let groqApiKey: String

    init(store: ArtifactStore, groqApiKey: String) {
        self.store = store
        self.groqApiKey = groqApiKey
    }

    // MARK: - Phase Reading

    func readPhase(from filename: String, phaseNumber: Int) -> String? {
        guard let content = store.read(filename: filename) else {
            logError("Cannot read phase from non-existent file: \(filename)", component: "PhaseEditor")
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
            logError("Phase \(phaseNumber) not found", component: "PhaseEditor")
            return nil
        }

        let result = phaseContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        log("Read phase \(phaseNumber) (\(result.count) chars)", category: .artifacts, component: "PhaseEditor")
        return result
    }

    // MARK: - Phase Split

    func splitPhase(_ phaseNumber: Int, instructions: String) async -> Bool {
        guard let content = store.read(filename: "phasing.md") else {
            logError("Cannot split phase - phasing.md not found", component: "PhaseEditor")
            return false
        }

        // Parse current phases
        let phases = PhaseParser.parsePhases(from: content)

        guard let targetPhase = phases.first(where: { $0.number == phaseNumber }) else {
            logError("Phase \(phaseNumber) not found for splitting", component: "PhaseEditor")
            return false
        }

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
            let success = store.write(filename: "phasing.md", content: newContent)

            if success {
                log("Successfully split phase \(phaseNumber) into \(subPhases.count) sub-phases", category: .artifacts, component: "PhaseEditor")
            }

            return success
        } catch {
            logError("Failed to split phase: \(error)", component: "PhaseEditor")
            return false
        }
    }

    // MARK: - Phase Merge

    func mergePhases(_ startPhase: Int, _ endPhase: Int, instructions: String?) async -> Bool {
        guard let content = store.read(filename: "phasing.md") else {
            logError("Cannot merge phases - phasing.md not found", component: "PhaseEditor")
            return false
        }

        // Validate consecutive phases (allow merging 2-5 phases)
        guard endPhase > startPhase else {
            logError("Invalid phase range: end phase (\(endPhase)) must be greater than start phase (\(startPhase))", component: "PhaseEditor")
            return false
        }

        let phaseCount = endPhase - startPhase + 1
        guard phaseCount <= 5 else {
            logError("Cannot merge \(phaseCount) phases. Maximum is 5 phases at once. Try merging phases \(startPhase)-\(startPhase + 4) first.", component: "PhaseEditor")
            return false
        }

        // Parse current phases
        let phases = PhaseParser.parsePhases(from: content)

        // Get phases to merge
        let phasesToMerge = phases.filter { $0.number >= startPhase && $0.number <= endPhase }

        guard phasesToMerge.count == (endPhase - startPhase + 1) else {
            logError("Not all phases from \(startPhase) to \(endPhase) exist", component: "PhaseEditor")
            return false
        }

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
            let success = store.write(filename: "phasing.md", content: newContent)

            if success {
                log("Successfully merged phases \(startPhase)-\(endPhase) into phase \(startPhase)", category: .artifacts, component: "PhaseEditor")
            }

            return success
        } catch {
            logError("Failed to merge phases: \(error)", component: "PhaseEditor")
            return false
        }
    }

    // MARK: - Phase Edit

    func editPhase(_ phaseNumber: Int, instructions: String) async -> Bool {
        guard let content = store.read(filename: "phasing.md") else {
            logError("Cannot edit phase - phasing.md not found", component: "PhaseEditor")
            return false
        }

        // Parse current phases
        let phases = PhaseParser.parsePhases(from: content)

        guard let targetPhaseIndex = phases.firstIndex(where: { $0.number == phaseNumber }) else {
            logError("Phase \(phaseNumber) not found for editing", component: "PhaseEditor")
            return false
        }

        let targetPhase = phases[targetPhaseIndex]

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
                log("Edit phase AI response: \(content)", category: .artifacts, component: "PhaseEditor")

                if let data = content.data(using: String.Encoding.utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    let title = json["title"] as? String
                    let description = json["description"] as? String

                    // Handle DoD that might be a string, array, or object
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
                        let success = store.write(filename: "phasing.md", content: newContent)

                        if success {
                            log("Successfully edited phase \(phaseNumber)", category: .artifacts, component: "PhaseEditor")
                        }

                        return success
                    } else {
                        logError("Missing fields in edit response. Title: \(title ?? "nil"), Description: \(description ?? "nil"), DoD: \(dod ?? "nil")", component: "PhaseEditor")
                    }
                } else {
                    logError("Failed to parse JSON from edit response", component: "PhaseEditor")
                }
            } else {
                logError("Failed to get AI response content", component: "PhaseEditor")
            }
            return false

        } catch {
            logError("Failed to edit phase: \(error)", component: "PhaseEditor")
            return false
        }
    }
}
