import Foundation

// MARK: - Phase Model

struct Phase {
    let number: Int
    let title: String
    let description: String
    let definitionOfDone: String

    /// Convert back to markdown format (using new format without **Description:** prefix)
    func toMarkdown() -> String {
        var lines: [String] = []
        lines.append("## Phase \(number): \(title)")
        lines.append(description)
        lines.append("**Definition of Done:** \(definitionOfDone)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Phase Parser

class PhaseParser {

    /// Parse a phasing.md content string into structured Phase objects
    static func parsePhases(from content: String) -> [Phase] {
        let lines = content.components(separatedBy: .newlines)
        var phases: [Phase] = []

        var currentPhaseNumber: Int?
        var currentPhaseTitle: String?
        var currentDescription: String?
        var currentDoD: String?
        var collectingDescription = false

        for (_, line) in lines.enumerated() {
            // Check for phase header: ## Phase N: Title
            if line.hasPrefix("## Phase ") {
                // Save previous phase if exists
                if let number = currentPhaseNumber,
                   let title = currentPhaseTitle,
                   let desc = currentDescription,
                   let dod = currentDoD {
                    phases.append(Phase(
                        number: number,
                        title: title,
                        description: desc,
                        definitionOfDone: dod
                    ))
                }

                // Parse new phase header
                let headerPattern = #"## Phase (\d+):\s*(.+)"#
                if let regex = try? NSRegularExpression(pattern: headerPattern),
                   let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {

                    if let numberRange = Range(match.range(at: 1), in: line),
                       let titleRange = Range(match.range(at: 2), in: line),
                       let number = Int(line[numberRange]) {
                        currentPhaseNumber = number
                        currentPhaseTitle = String(line[titleRange])
                        currentDescription = nil
                        currentDoD = nil
                        collectingDescription = true
                    }
                }
            }
            // Check for description line with prefix (old format)
            else if line.hasPrefix("**Description:**") {
                let desc = line.replacingOccurrences(of: "**Description:**", with: "").trimmingCharacters(in: .whitespaces)
                currentDescription = desc
                collectingDescription = false
            }
            // Check for definition of done
            else if line.hasPrefix("**Definition of Done:**") {
                let dod = line.replacingOccurrences(of: "**Definition of Done:**", with: "").trimmingCharacters(in: .whitespaces)
                currentDoD = dod
                collectingDescription = false
            }
            // Handle new format where description is just a paragraph after the phase title
            else if collectingDescription && !line.isEmpty && currentPhaseNumber != nil && currentDescription == nil {
                currentDescription = line
                collectingDescription = false
            }
        }

        // Save final phase if exists
        if let number = currentPhaseNumber,
           let title = currentPhaseTitle,
           let desc = currentDescription,
           let dod = currentDoD {
            phases.append(Phase(
                number: number,
                title: title,
                description: desc,
                definitionOfDone: dod
            ))
        }

        log("Parsed \(phases.count) phases from content", category: .artifacts, component: "PhaseParser")
        return phases
    }

    /// Convert phases array back to markdown content
    static func phasesToMarkdown(_ phases: [Phase]) -> String {
        var lines: [String] = []
        lines.append("# Project Phasing")
        lines.append("")

        for phase in phases.sorted(by: { $0.number < $1.number }) {
            lines.append(phase.toMarkdown())
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Split a phase into multiple sub-phases based on instructions
    static func splitPhase(_ phase: Phase, instructions: String, groqApiKey: String) async throws -> [Phase] {
        // Use AI to intelligently split the phase based on instructions
        let prompt = """
        Split this phase into multiple sub-phases based on the instructions.

        Original Phase:
        Title: \(phase.title)
        Description: \(phase.description)
        Definition of Done: \(phase.definitionOfDone)

        Instructions: \(instructions)

        Generate 2-4 sub-phases that break down this work. Each sub-phase should have:
        - A clear title
        - A specific description
        - A testable definition of done

        Return JSON object with a "phases" array containing objects with: title, description, definitionOfDone
        Example format:
        {
          "phases": [
            {"title": "...", "description": "...", "definitionOfDone": "..."},
            {"title": "...", "description": "...", "definitionOfDone": "..."}
          ]
        }
        """

        let apiURL = "https://api.groq.com/openai/v1/chat/completions"

        let requestBody: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "system", "content": "You are a project planning assistant. Generate clear, actionable phase splits in JSON format."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3
        ]

        let headers = [
            "Authorization": "Bearer \(groqApiKey)",
            "Content-Type": "application/json"
        ]

        let response = try await NetworkManager.shared.post(url: apiURL, body: requestBody, headers: headers)

        // Parse response
        if let choices = response["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {

            // Log the raw content for debugging
            log("Split AI response: \(content)", category: .artifacts, component: "PhaseParser")

            if let data = content.data(using: String.Encoding.utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Try both "phases" and "subPhases" keys for compatibility
                let subPhases = (json["phases"] as? [[String: Any]]) ?? (json["subPhases"] as? [[String: Any]])

                if let subPhases = subPhases {

                    var resultPhases: [Phase] = []
                    for (_, subPhase) in subPhases.enumerated() {
                        if let title = subPhase["title"] as? String,
                           let description = subPhase["description"] as? String,
                           let dod = subPhase["definitionOfDone"] as? String {
                            // We'll handle renumbering in the manager
                            let subNumber = phase.number
                            resultPhases.append(Phase(
                                number: subNumber,
                                title: title,
                                description: description,
                                definitionOfDone: dod
                            ))
                        }
                    }

                    log("Split phase \(phase.number) into \(resultPhases.count) sub-phases", category: .artifacts, component: "PhaseParser")
                    return resultPhases
                }
            } else {
                logError("Failed to parse JSON from split response: \(content)", component: "PhaseParser")
            }
        }

        throw NSError(domain: "PhaseParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse split phase response"])
    }

    /// Merge multiple phases into one based on instructions
    static func mergePhases(_ phases: [Phase], instructions: String?, groqApiKey: String) async throws -> Phase {
        // Use AI to intelligently merge phases
        let phaseDescriptions = phases.map { phase in
            """
            Phase \(phase.number): \(phase.title)
            Description: \(phase.description)
            DoD: \(phase.definitionOfDone)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Merge these phases into a single cohesive phase.

        Phases to merge:
        \(phaseDescriptions)

        \(instructions.map { "Additional instructions: \($0)" } ?? "")

        Generate a merged phase that combines the work. The merged phase should have:
        - A comprehensive title that captures all the work
        - A description that encompasses all aspects
        - A definition of done that ensures all original work is complete

        Return JSON with: title, description, definitionOfDone
        """

        let apiURL = "https://api.groq.com/openai/v1/chat/completions"

        let requestBody: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": [
                ["role": "system", "content": "You are a project planning assistant. Generate clear, comprehensive merged phases in JSON format."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.3
        ]

        let headers = [
            "Authorization": "Bearer \(groqApiKey)",
            "Content-Type": "application/json"
        ]

        let response = try await NetworkManager.shared.post(url: apiURL, body: requestBody, headers: headers)

        // Parse response
        if let choices = response["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {

            // Log the raw content for debugging
            log("Merge AI response: \(content)", category: .artifacts, component: "PhaseParser")

            if let data = content.data(using: String.Encoding.utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Handle both [String: String] and [String: Any] formats
                let title = json["title"] as? String
                let description = json["description"] as? String

                // Handle DoD that might be a string, array, or object
                var dod: String?
                if let dodString = json["definitionOfDone"] as? String {
                    dod = dodString
                } else if let dodArray = json["definitionOfDone"] as? [String] {
                    // Join array elements if AI returns array
                    dod = dodArray.joined(separator: ". ")
                } else if let dodObject = json["definitionOfDone"] as? [String: Any] {
                    // Handle nested object format (e.g., {"criteria": [...]} )
                    if let criteria = dodObject["criteria"] as? [String] {
                        dod = criteria.joined(separator: ". ")
                    } else if let criteriaString = dodObject["criteria"] as? String {
                        dod = criteriaString
                    } else {
                        // Try to get any string value from the object
                        let values = dodObject.values.compactMap { $0 as? String }
                        if !values.isEmpty {
                            dod = values.joined(separator: ". ")
                        }
                    }
                }

                if let title = title,
                   let description = description,
                   let dod = dod {

                    let mergedPhase = Phase(
                        number: phases[0].number, // Use first phase number
                        title: title,
                        description: description,
                        definitionOfDone: dod
                    )

                    log("Merged \(phases.count) phases into phase \(mergedPhase.number)", category: .artifacts, component: "PhaseParser")
                    return mergedPhase
                }

                logError("Missing fields in merge response. Title: \(title ?? "nil"), Description: \(description ?? "nil"), DoD: \(dod ?? "nil")", component: "PhaseParser")
            } else {
                logError("Failed to parse JSON from merge response: \(content)", component: "PhaseParser")
            }
        }

        throw NSError(domain: "PhaseParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse merge phase response"])
    }

    /// Renumber phases after split/merge operations
    static func renumberPhases(_ phases: [Phase]) -> [Phase] {
        let sorted = phases.sorted { $0.number < $1.number }
        var renumbered: [Phase] = []

        for (index, phase) in sorted.enumerated() {
            renumbered.append(Phase(
                number: index + 1,
                title: phase.title,
                description: phase.description,
                definitionOfDone: phase.definitionOfDone
            ))
        }

        return renumbered
    }
}