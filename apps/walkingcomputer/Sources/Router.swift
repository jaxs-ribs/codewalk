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
    case conversation(String)
    case repeatLast
    case nextPhase
    case previousPhase
    case stop
    case copyDescription
    case copyPhasing
    case copyBoth
    case search(String)  // New action for search

    // Custom coding for enum with associated values
    enum CodingKeys: String, CodingKey {
        case action
        case content
        case phaseNumber
        case query  // For search
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
        case "edit_phasing":
            let content = try container.decode(String.self, forKey: .content)
            let phaseNumber = try container.decodeIfPresent(Int.self, forKey: .phaseNumber)
            self = .editPhasing(phaseNumber: phaseNumber, content: content)
        case "conversation":
            let content = try container.decode(String.self, forKey: .content)
            self = .conversation(content)
        case "repeat_last":
            self = .repeatLast
        case "next_phase":
            self = .nextPhase
        case "previous_phase":
            self = .previousPhase
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
        default:
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
        case .conversation(let content):
            try container.encode("conversation", forKey: .action)
            try container.encode(content, forKey: .content)
        case .repeatLast:
            try container.encode("repeat_last", forKey: .action)
        case .nextPhase:
            try container.encode("next_phase", forKey: .action)
        case .previousPhase:
            try container.encode("previous_phase", forKey: .action)
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
    Voice router. Default to conversation unless clear command intent.

    COMMAND PATTERNS:
    - Contains "write" + "description/phasing" → write_*
    - Contains "read" + "description/phasing/phase X" → read_*
    - Contains "edit/change/update" + target → edit_*
    - Contains "search" + anything → search (extract query after "search")
    - Contains "copy" + target → copy_*
    - Exact: "repeat/stop/next/previous" → respective action

    CONVERSATION:
    - Project ideas, features, requirements
    - Questions without command verbs
    - Statements and acknowledgments

    JSON format:
    {
        "intent": "directive|conversation",
        "action": {
            "action": "name",
            "content": "message/edit content",
            "phaseNumber": if_applicable,
            "query": "if_search"
        },
        "reasoning": "brief"
    }
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
