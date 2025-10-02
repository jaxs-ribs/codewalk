import Foundation

// MARK: - Intent Types

enum Intent: String, Codable {
    case directive = "directive"
    case conversation = "conversation"
}

// MARK: - Fluid Actions (Phase 2-5: Simplified primitives)
// These 4 primitives replace 18 discrete actions for a cleaner API

enum FluidAction: Codable {
    case write(artifact: String, instructions: String?)
    case read(artifact: String, scope: String?)
    case search(query: String, depth: String?)
    case copy(artifact: String)
    case conversation(String)

    enum CodingKeys: String, CodingKey {
        case action
        case artifact
        case instructions
        case scope
        case query
        case depth
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)

        switch action {
        case "write":
            let artifact = try container.decode(String.self, forKey: .artifact)
            let instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
            self = .write(artifact: artifact, instructions: instructions)
        case "read":
            let artifact = try container.decode(String.self, forKey: .artifact)
            let scope = try container.decodeIfPresent(String.self, forKey: .scope)
            self = .read(artifact: artifact, scope: scope)
        case "search":
            let query = try container.decode(String.self, forKey: .query)
            let depth = try container.decodeIfPresent(String.self, forKey: .depth)
            self = .search(query: query, depth: depth)
        case "copy":
            let artifact = try container.decode(String.self, forKey: .artifact)
            self = .copy(artifact: artifact)
        case "conversation":
            let content = try container.decode(String.self, forKey: .content)
            self = .conversation(content)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unknown fluid action: \(action)"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .write(let artifact, let instructions):
            try container.encode("write", forKey: .action)
            try container.encode(artifact, forKey: .artifact)
            try container.encodeIfPresent(instructions, forKey: .instructions)
        case .read(let artifact, let scope):
            try container.encode("read", forKey: .action)
            try container.encode(artifact, forKey: .artifact)
            try container.encodeIfPresent(scope, forKey: .scope)
        case .search(let query, let depth):
            try container.encode("search", forKey: .action)
            try container.encode(query, forKey: .query)
            try container.encodeIfPresent(depth, forKey: .depth)
        case .copy(let artifact):
            try container.encode("copy", forKey: .action)
            try container.encode(artifact, forKey: .artifact)
        case .conversation(let content):
            try container.encode("conversation", forKey: .action)
            try container.encode(content, forKey: .content)
        }
    }

    // Convert fluid action to discrete action for backward compatibility
    func toDiscreteAction() -> ProposedAction {
        switch self {
        case .write(let artifact, let instructions):
            switch artifact.lowercased() {
            case "spec", "both":
                return .writeBoth
            case "description":
                if let inst = instructions {
                    return .editDescription(inst)
                }
                return .writeDescription
            case "phasing":
                // Parse instructions for phase operations
                if let inst = instructions {
                    let lower = inst.lowercased()
                    // Check for merge
                    if lower.contains("merge") {
                        if let range = extractPhaseRange(from: inst) {
                            return .mergePhases(startPhase: range.start, endPhase: range.end, instructions: inst)
                        }
                    }
                    // Check for split
                    if lower.contains("split") {
                        if let phaseNum = extractPhaseNumber(from: inst) {
                            return .splitPhase(phaseNumber: phaseNum, instructions: inst)
                        }
                    }
                    // Check for specific phase edit
                    if let phaseNum = extractPhaseNumber(from: inst) {
                        return .editPhasing(phaseNumber: phaseNum, content: inst)
                    }
                    return .editPhasing(phaseNumber: nil, content: inst)
                }
                return .writePhasing
            default:
                return .conversation("write \(artifact)")
            }

        case .read(let artifact, let scope):
            let lower = artifact.lowercased()
            // Determine scope for phases range or single
            if let scope = scope {
                if let range = extractPhaseRange(from: scope) {
                    return .readPhaseRange(startPhase: range.start, endPhase: range.end)
                }
                if let phaseNum = extractPhaseNumber(from: scope) {
                    return .readSpecificPhase(phaseNum)
                }
            }
            switch lower {
            case "spec", "both":
                // Default to reading both via description then phasing in orchestrator
                return .readDescription
            case "description":
                return .readDescription
            case "phasing":
                return .readPhasing
            default:
                return .conversation("read \(artifact)")
            }

        case .search(let query, let depth):
            if depth == "deep" || depth == "research" {
                return .deepSearch(query)
            }
            return .search(query)

        case .copy(let artifact):
            switch artifact.lowercased() {
            case "spec", "both":
                return .copyBoth
            case "description":
                return .copyDescription
            case "phasing":
                return .copyPhasing
            default:
                return .copyBoth
            }

        case .conversation(let content):
            return .conversation(content)
        }
    }

    private func extractPhaseNumber(from text: String) -> Int? {
        let patterns = [
            "phase\\s+(\\d+)",
            "(\\d+)\\s*phase",
            "phase\\s+([a-z]+)",  // for "phase one", "phase two", etc.
            "#(\\d+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    let captured = String(text[range])

                    // Handle word numbers
                    let wordToNum = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                                     "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
                    if let num = wordToNum[captured.lowercased()] {
                        return num
                    }

                    // Handle numeric
                    if let num = Int(captured) {
                        return num
                    }
                }
            }
        }
        return nil
    }

    private func extractPhaseRange(from text: String) -> (start: Int, end: Int)? {
        // Normalize dashes and spacing
        let normalized = text
            .replacingOccurrences(of: "\u{2013}", with: "-") // en dash
            .replacingOccurrences(of: "\u{2014}", with: "-") // em dash
            .lowercased()

        // Word to number map for simple ranges
        let wordToNum: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
        ]

        // Try numeric patterns first
        let patterns = [
            "phases?\\s+(\\d+)\\s*(?:to|through|thru|-)\\s*(\\d+)",
            "(\\d+)\\s*(?:to|through|thru|-)\\s*(\\d+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                if let r1 = Range(match.range(at: 1), in: normalized),
                   let r2 = Range(match.range(at: 2), in: normalized),
                   let start = Int(normalized[r1]),
                   let end = Int(normalized[r2]) {
                    return (start, end)
                }
            }
        }

        // Try word-number ranges like "phases two to four"
        let wordRangePatterns = [
            "phases?\\s+([a-z]+)\\s*(?:to|through|thru|-)\\s*([a-z]+)",
            "([a-z]+)\\s*(?:to|through|thru|-)\\s*([a-z]+)"
        ]
        for pattern in wordRangePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                if let r1 = Range(match.range(at: 1), in: normalized),
                   let r2 = Range(match.range(at: 2), in: normalized) {
                    let s = String(normalized[r1])
                    let e = String(normalized[r2])
                    if let start = wordToNum[s], let end = wordToNum[e] {
                        return (start, end)
                    }
                }
            }
        }

        // Try conjunction pattern "phases 2 and 3"
        if let regex = try? NSRegularExpression(pattern: "phases?\\s+(\\d+)\\s*and\\s*(\\d+)", options: .caseInsensitive),
           let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let r1 = Range(match.range(at: 1), in: normalized),
           let r2 = Range(match.range(at: 2), in: normalized),
           let start = Int(normalized[r1]), let end = Int(normalized[r2]) {
            return (start, end)
        }

        return nil
    }
}

// MARK: - Proposed Actions (Legacy discrete actions - maintained for backward compatibility)
// Phase 5: These are now generated from fluid actions via toDiscreteAction()
// New code should use fluid actions directly

enum ProposedAction: Codable {
    case writeDescription
    case writePhasing
    case writeBoth
    case readDescription
    case readPhasing
    case readSpecificPhase(Int)
    case readPhaseRange(startPhase: Int, endPhase: Int)
    case editDescription(String)
    case editPhasing(phaseNumber: Int?, content: String)
    case splitPhase(phaseNumber: Int, instructions: String)
    case mergePhases(startPhase: Int, endPhase: Int, instructions: String?)
    case conversation(String)
    case repeatLast
    case stop
    case copyDescription
    case copyPhasing
    case copyBoth
    case search(String)  // Shallow search (small depth)
    case deepSearch(String)  // Deep research (medium depth)

    // Custom coding for enum with associated values
    enum CodingKeys: String, CodingKey {
        case action
        case content
        case phaseNumber
        case query  // For search
        case instructions  // For split/merge
        case startPhase  // For merge
        case endPhase  // For merge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)

        switch action {
        case "write_description":
            self = .writeDescription
        case "write_phasing":
            self = .writePhasing
        case "write_both":
            self = .writeBoth
        case "read_description":
            self = .readDescription
        case "read_phasing":
            self = .readPhasing
        case "read_specific_phase":
            let phaseNumber = try container.decode(Int.self, forKey: .phaseNumber)
            self = .readSpecificPhase(phaseNumber)
        case "read_phase_range":
            let start = try container.decode(Int.self, forKey: .startPhase)
            let end = try container.decode(Int.self, forKey: .endPhase)
            self = .readPhaseRange(startPhase: start, endPhase: end)
        case "edit_description":
            let content = try container.decode(String.self, forKey: .content)
            self = .editDescription(content)
        case "edit_phasing", "edit_phase":  // Handle common variation
            let content = try container.decode(String.self, forKey: .content)
            let phaseNumber = try container.decodeIfPresent(Int.self, forKey: .phaseNumber)
            self = .editPhasing(phaseNumber: phaseNumber, content: content)
        case "split_phase":
            let phaseNumber = try container.decode(Int.self, forKey: .phaseNumber)
            let instructions = try container.decode(String.self, forKey: .instructions)
            self = .splitPhase(phaseNumber: phaseNumber, instructions: instructions)
        case "merge_phases":
            let startPhase = try container.decode(Int.self, forKey: .startPhase)
            let endPhase = try container.decode(Int.self, forKey: .endPhase)
            let instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
            self = .mergePhases(startPhase: startPhase, endPhase: endPhase, instructions: instructions)
        case "conversation":
            let content = try container.decode(String.self, forKey: .content)
            self = .conversation(content)
        case "repeat_last":
            self = .repeatLast
        case "stop":
            self = .stop
        case "copy_description":
            self = .copyDescription
        case "copy_phasing":
            self = .copyPhasing
        case "copy_both":
            self = .copyBoth
        case "search":
            let query = try container.decode(String.self, forKey: .query)
            self = .search(query)
        case "deep_search":
            let query = try container.decode(String.self, forKey: .query)
            self = .deepSearch(query)
        default:
            // Log the unknown action for debugging
            log("Warning: Unknown action '\(action)' - falling back to error", category: .router, component: "Router")
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Unknown action: \(action)"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .writeDescription:
            try container.encode("write_description", forKey: .action)
        case .writePhasing:
            try container.encode("write_phasing", forKey: .action)
        case .writeBoth:
            try container.encode("write_both", forKey: .action)
        case .readDescription:
            try container.encode("read_description", forKey: .action)
        case .readPhasing:
            try container.encode("read_phasing", forKey: .action)
        case .readSpecificPhase(let phaseNumber):
            try container.encode("read_specific_phase", forKey: .action)
            try container.encode(phaseNumber, forKey: .phaseNumber)
        case .readPhaseRange(let start, let end):
            try container.encode("read_phase_range", forKey: .action)
            try container.encode(start, forKey: .startPhase)
            try container.encode(end, forKey: .endPhase)
        case .editDescription(let content):
            try container.encode("edit_description", forKey: .action)
            try container.encode(content, forKey: .content)
        case .editPhasing(let phaseNumber, let content):
            try container.encode("edit_phasing", forKey: .action)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(phaseNumber, forKey: .phaseNumber)
        case .splitPhase(let phaseNumber, let instructions):
            try container.encode("split_phase", forKey: .action)
            try container.encode(phaseNumber, forKey: .phaseNumber)
            try container.encode(instructions, forKey: .instructions)
        case .mergePhases(let startPhase, let endPhase, let instructions):
            try container.encode("merge_phases", forKey: .action)
            try container.encode(startPhase, forKey: .startPhase)
            try container.encode(endPhase, forKey: .endPhase)
            try container.encodeIfPresent(instructions, forKey: .instructions)
        case .conversation(let content):
            try container.encode("conversation", forKey: .action)
            try container.encode(content, forKey: .content)
        case .repeatLast:
            try container.encode("repeat_last", forKey: .action)
        case .stop:
            try container.encode("stop", forKey: .action)
        case .copyDescription:
            try container.encode("copy_description", forKey: .action)
        case .copyPhasing:
            try container.encode("copy_phasing", forKey: .action)
        case .copyBoth:
            try container.encode("copy_both", forKey: .action)
        case .search(let query):
            try container.encode("search", forKey: .action)
            try container.encode(query, forKey: .query)
        case .deepSearch(let query):
            try container.encode("deep_search", forKey: .action)
            try container.encode(query, forKey: .query)
        }
    }
}

// MARK: - Router Responses

// Fluid router response for natural language routing
struct FluidRouterResponse: Codable {
    let intent: Intent
    let action: FluidAction
    let reasoning: String?
}

// Legacy router response for backward compatibility
struct RouterResponse: Codable {
    let intent: Intent
    let action: ProposedAction
    let reasoning: String?
}

// Dual routing response that tries fluid first, then discrete
struct DualRoutingResult {
    let discrete: ProposedAction
    let fluid: FluidAction?
    let reasoning: String?

    var wasFluidRoute: Bool {
        return fluid != nil
    }
}

struct RouterContext {
    let recentMessages: [String]
    let lastSearchQuery: String?

    static let empty = RouterContext(recentMessages: [], lastSearchQuery: nil)
}

// MARK: - Router

class Router {
    private let groqApiKey: String
    private let modelId: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    // New fluid routing prompt - natural language understanding
    private let fluidSystemPrompt = """
    Route user input to one of 4 core actions. Understand natural language intent.

    ACTIONS:
    1. write(artifact, instructions?) - Create or modify content
    2. read(artifact, scope?) - Read content or specific sections
    3. search(query, depth?) - Search the web
    4. copy(artifact) - Copy to clipboard

    ARTIFACTS: "spec" (both), "description", "phasing"
    DEPTH: "deep" for research, null for quick search
    SCOPE: "phase X" (single) or "phases X to Y" (range) to read

    EXAMPLES:
    "write everything" → {"intent": "directive", "action": {"action": "write", "artifact": "spec"}}
    "write the spec" → {"intent": "directive", "action": {"action": "write", "artifact": "spec"}}
    "write a spec" → {"intent": "directive", "action": {"action": "write", "artifact": "spec"}}
    "update the description to be shorter" → {"intent": "directive", "action": {"action": "write", "artifact": "description", "instructions": "make it shorter"}}
    "merge phases 2 and 3" → {"intent": "directive", "action": {"action": "write", "artifact": "phasing", "instructions": "merge phases 2 and 3"}}
    "split phase 3 into frontend and backend" → {"intent": "directive", "action": {"action": "write", "artifact": "phasing", "instructions": "split phase 3 into frontend and backend"}}
    "read the whole thing" → {"intent": "directive", "action": {"action": "read", "artifact": "spec"}}
    "read the spec" → {"intent": "directive", "action": {"action": "read", "artifact": "spec"}}
    "what's in phase 5?" → {"intent": "directive", "action": {"action": "read", "artifact": "phasing", "scope": "phase 5"}}
    "show me phases 2 through 4" → {"intent": "directive", "action": {"action": "read", "artifact": "phasing", "scope": "phases 2 through 4"}}
    "search for swift async" → {"intent": "directive", "action": {"action": "search", "query": "swift async"}}
    "deep dive into kubernetes" → {"intent": "directive", "action": {"action": "search", "query": "kubernetes", "depth": "deep"}}
    "copy everything" → {"intent": "directive", "action": {"action": "copy", "artifact": "spec"}}
    "how does X work?" → {"intent": "conversation", "action": {"action": "conversation", "content": "how does X work?"}}

    WRITE/EDIT MAPPING:
    - Phrases like "update", "rewrite", "make X more Y", "rework" should map to write(artifact, instructions)
    - If user says "update the description/spec/phasing ...", set artifact accordingly and include the instruction text

    Return JSON with intent and action. Be flexible with phrasing but precise with routing.
    """

    // Legacy discrete routing prompt for fallback
    private let systemPrompt = """
    Route user input to appropriate action. Return EXACT JSON format shown in examples.

    ACTIONS AND EXACT JSON FORMATS:

    SEARCH:
    "search for X" → {"intent": "directive", "action": {"action": "search", "query": "X"}}
    "look up X" → {"intent": "directive", "action": {"action": "search", "query": "X"}}

    DEEP SEARCH:
    "deep research X" → {"intent": "directive", "action": {"action": "deep_search", "query": "X"}}
    "research X thoroughly" → {"intent": "directive", "action": {"action": "deep_search", "query": "X"}}

    WRITE:
    "write the description" → {"intent": "directive", "action": {"action": "write_description"}}
    "write the phasing" → {"intent": "directive", "action": {"action": "write_phasing"}}
    "write both/write both artifacts" → {"intent": "directive", "action": {"action": "write_both"}}
    "write description and phasing" → {"intent": "directive", "action": {"action": "write_both"}}
    "write the spec" → {"intent": "directive", "action": {"action": "write_both"}}

    READ:
    "read the description" → {"intent": "directive", "action": {"action": "read_description"}}
    "read the phasing" → {"intent": "directive", "action": {"action": "read_phasing"}}
    "read phase 1" → {"intent": "directive", "action": {"action": "read_specific_phase", "phaseNumber": 1}}
    "read me phase two" → {"intent": "directive", "action": {"action": "read_specific_phase", "phaseNumber": 2}}
    "show me phases 2 through 4" → {"intent": "directive", "action": {"action": "read_phase_range", "startPhase": 2, "endPhase": 4}}

    EDIT:
    "edit the description to say X" → {"intent": "directive", "action": {"action": "edit_description", "content": "X"}}
    "edit the phasing" → {"intent": "directive", "action": {"action": "edit_phasing", "content": "..."}}
    "edit phase 2 to include X" → {"intent": "directive", "action": {"action": "edit_phasing", "phaseNumber": 2, "content": "include X"}}
    "change phase 1 to Y" → {"intent": "directive", "action": {"action": "edit_phasing", "phaseNumber": 1, "content": "Y"}}

    UPDATE/REWRITE:
    "update the description to be shorter" → {"intent": "directive", "action": {"action": "edit_description", "content": "be shorter"}}
    "rewrite the phasing with smaller phases" → {"intent": "directive", "action": {"action": "edit_phasing", "content": "smaller phases"}}

    SPLIT/MERGE PHASES:
    "split phase 2 into frontend and backend work" → {"intent": "directive", "action": {"action": "split_phase", "phaseNumber": 2, "instructions": "frontend and backend work"}}
    "break phase 3 into smaller tasks" → {"intent": "directive", "action": {"action": "split_phase", "phaseNumber": 3, "instructions": "smaller tasks"}}
    "merge phases 5 and 6" → {"intent": "directive", "action": {"action": "merge_phases", "startPhase": 5, "endPhase": 6}}
    "combine phases 2 and 3 into one" → {"intent": "directive", "action": {"action": "merge_phases", "startPhase": 2, "endPhase": 3}}
    "merge phases 1 through 3" → {"intent": "directive", "action": {"action": "merge_phases", "startPhase": 1, "endPhase": 3}}

    COPY:
    "copy description" → {"intent": "directive", "action": {"action": "copy_description"}}
    "copy phasing" → {"intent": "directive", "action": {"action": "copy_phasing"}}
    "copy both" → {"intent": "directive", "action": {"action": "copy_both"}}

    NAVIGATION:
    "repeat" → {"intent": "directive", "action": {"action": "repeat_last"}}
    "stop" → {"intent": "directive", "action": {"action": "stop"}}
    "next phase" → {"intent": "directive", "action": {"action": "next_phase"}}
    "previous phase" → {"intent": "directive", "action": {"action": "previous_phase"}}

    CONVERSATION (default for questions/discussion):
    "how does X work?" → {"intent": "conversation", "action": {"action": "conversation", "content": "how does X work?"}}
    "I want to build X" → {"intent": "conversation", "action": {"action": "conversation", "content": "I want to build X"}}

    CRITICAL: Use EXACT action names shown above (e.g., "edit_phasing" not "edit_phase")
    """

    init(groqApiKey: String, modelId: String) {
        self.groqApiKey = groqApiKey
        self.modelId = modelId
    }

    func route(transcript: String, context: RouterContext) async throws -> RouterResponse {
        log("Analyzing user intent...", category: .router)

        // Truncate very long transcripts to prevent token limit errors
        let truncatedTranscript = transcript.count > 1500
            ? String(transcript.prefix(1500)) + "..."
            : transcript

        let userContent = buildContextPrompt(transcript: truncatedTranscript, context: context)

        // Create request
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let requestBody: [String: Any] = [
            "model": modelId,  // Using configured model
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.1,
            "max_tokens": 400,  // Increased from 200 to handle longer responses
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        log("Sending request to Groq API...", category: .router)

        // Perform request with retry logic
        let data = try await NetworkManager.shared.performRequestWithRetry(request)

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "Router", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        log("Response received from LLM", category: .router)
        // Log detailed response in debug mode
        #if DEBUG
        log("Raw LLM response: \(content)", category: .router)
        #endif

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "Router", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse content"])
        }

        let routerResponse = try JSONDecoder().decode(RouterResponse.self, from: contentData)

        log("Intent: \(routerResponse.intent), Action: \(routerResponse.action)", category: .router)

        return routerResponse
    }

    // MARK: - Dual Routing (Fluid first, then discrete fallback)

    func routeWithDualMode(transcript: String, context: RouterContext) async throws -> RouterResponse {
        log("Starting dual-mode routing (fluid first)...", category: .router)

        // Try fluid routing first
        do {
            let fluidResult = try await routeFluid(transcript: transcript, context: context)

            // Convert fluid action to discrete for backward compatibility
            let discreteAction = fluidResult.action.toDiscreteAction()

            // Log the dual routing decision
            log("✅ Fluid route succeeded", category: .router)
            log("  Fluid: \(fluidResult.action)", category: .router)
            log("  Discrete: \(discreteAction)", category: .router)

            return RouterResponse(
                intent: fluidResult.intent,
                action: discreteAction,
                reasoning: fluidResult.reasoning
            )
        } catch {
            // Fluid routing failed, fall back to discrete
            log("⚠️ Fluid routing failed, falling back to discrete", category: .router)
            log("  Error: \(error)", category: .router)

            return try await route(transcript: transcript, context: context)
        }
    }

    // Fluid routing using natural language understanding
    private func routeFluid(transcript: String, context: RouterContext) async throws -> FluidRouterResponse {
        log("Attempting fluid routing...", category: .router)

        // Truncate very long transcripts to prevent token limit errors
        let truncatedTranscript = transcript.count > 1500
            ? String(transcript.prefix(1500)) + "..."
            : transcript

        let userContent = buildContextPrompt(transcript: truncatedTranscript, context: context)

        // Create request
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body with fluid prompt
        let requestBody: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": fluidSystemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.1,
            "max_tokens": 400,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Perform request
        let data = try await NetworkManager.shared.performRequestWithRetry(request)

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "Router", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid fluid response format"])
        }

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "Router", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse fluid content"])
        }

        let fluidResponse = try JSONDecoder().decode(FluidRouterResponse.self, from: contentData)

        log("Fluid Intent: \(fluidResponse.intent), Action: \(fluidResponse.action)", category: .router)

        return fluidResponse
    }

    private func buildContextPrompt(transcript: String, context: RouterContext) -> String {
        var sections: [String] = []

        if !context.recentMessages.isEmpty {
            let history = context.recentMessages.joined(separator: "\n")
            sections.append("Recent conversation (newest last):\n\(history)")
        }

        if let query = context.lastSearchQuery, !query.isEmpty {
            sections.append("Last search query: \(query)")
        }

        sections.append("Current user input: \(transcript)")

        return sections.joined(separator: "\n\n")
    }
}
