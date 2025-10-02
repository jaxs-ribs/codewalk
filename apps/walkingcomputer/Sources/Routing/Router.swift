import Foundation

// MARK: - Intent Types

enum Intent: String, Codable {
    case directive = "directive"
    case conversation = "conversation"
}

// MARK: - Proposed Actions

enum ProposedAction: Codable {
    case writeDescription
    case writePhasing
    case writeBoth
    case readDescription
    case readPhasing
    case readSpecificPhase(Int)
    case editDescription(String)
    case editPhasing(phaseNumber: Int?, content: String)
    case splitPhase(phaseNumber: Int, instructions: String)
    case mergePhases(startPhase: Int, endPhase: Int, instructions: String?)
    case conversation(String)
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

// MARK: - Router Response

struct RouterResponse: Codable {
    let intent: Intent
    let action: ProposedAction
    let reasoning: String?
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

    READ:
    "read the description" → {"intent": "directive", "action": {"action": "read_description"}}
    "read the phasing" → {"intent": "directive", "action": {"action": "read_phasing"}}
    "read phase 1" → {"intent": "directive", "action": {"action": "read_specific_phase", "phaseNumber": 1}}
    "read me phase two" → {"intent": "directive", "action": {"action": "read_specific_phase", "phaseNumber": 2}}

    EDIT:
    "edit the description to say X" → {"intent": "directive", "action": {"action": "edit_description", "content": "X"}}
    "edit the phasing" → {"intent": "directive", "action": {"action": "edit_phasing", "content": "..."}}
    "edit phase 2 to include X" → {"intent": "directive", "action": {"action": "edit_phasing", "phaseNumber": 2, "content": "include X"}}
    "change phase 1 to Y" → {"intent": "directive", "action": {"action": "edit_phasing", "phaseNumber": 1, "content": "Y"}}

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
