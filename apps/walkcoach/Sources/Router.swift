import Foundation

// MARK: - Intent Types

enum Intent: String, Codable {
    case directive = "directive"
    case conversation = "conversation"
    case clarification = "clarification"
}

// MARK: - Proposed Actions

enum ProposedAction: Codable {
    case writeDescription
    case writePhasing
    case readDescription
    case readPhasing
    case readSpecificPhase(Int)
    case editDescription(String)
    case editPhasing(phaseNumber: Int?, content: String)
    case conversation(String)
    case clarification(String)
    case repeatLast
    case nextPhase
    case previousPhase
    case stop
    case copyDescription
    case copyPhasing
    case copyBoth

    // Custom coding for enum with associated values
    enum CodingKeys: String, CodingKey {
        case action
        case content
        case phaseNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)

        switch action {
        case "write_description":
            self = .writeDescription
        case "write_phasing":
            self = .writePhasing
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
        case "clarification":
            let content = try container.decode(String.self, forKey: .content)
            self = .clarification(content)
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
        case .clarification(let content):
            try container.encode("clarification", forKey: .action)
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
        }
    }
}

// MARK: - Router Response

struct RouterResponse: Codable {
    let intent: Intent
    let action: ProposedAction
    let reasoning: String?
}

// MARK: - Router

class Router {
    private let groqApiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    private let systemPrompt = """
    You are a router for a voice-first note-taking speccer app. The app is designed for users to think out loud.

    CRITICAL ROUTING PHILOSOPHY:
    - DEFAULT to conversation unless there's an EXPLICIT command
    - Users will mostly be sharing ideas, not giving commands
    - Be very conservative about interpreting as directives

    ONLY route as directive for these EXPLICIT commands:
    - "write the description" or "write description" -> write_description
    - "write me a description" or "can you write a description" -> write_description
    - "write the phasing" or "write phasing" -> write_phasing
    - "read the description" or "read description" -> read_description
    - "read the phasing" or "read phasing" -> read_phasing
    - "read phase 2" or "read phase two" -> read_specific_phase with phaseNumber
    - "edit the description to..." or "edit it to..." -> edit_description
    - "add... to the description" or "can you add... to the description" -> edit_description
    - "please include... in the description" -> edit_description
    - "make sure to edit it so..." or "update the description to..." -> edit_description
    - "regenerate the description" or "rewrite the description" -> write_description
    - "change phase 2 to..." or "edit phase 2..." -> edit_phasing with phaseNumber
    - "add... to phase 2" or "include... in the phasing" -> edit_phasing
    - "regenerate the phasing" or "rewrite the phasing" -> write_phasing
    - "repeat" or "repeat last" -> repeat_last
    - "next" or "next phase" -> next_phase
    - "previous" or "previous phase" -> previous_phase
    - "stop" -> stop
    - "copy the description" or "copy description" -> copy_description
    - "copy the phasing" or "copy phasing" -> copy_phasing
    - "copy everything" or "copy both" -> copy_both

    EVERYTHING ELSE is conversation:
    - Project ideas and features
    - Requirements and constraints
    - Questions about the project
    - Thinking out loud
    - Vague mentions of description/phasing without "write" or "read"

    When in doubt, choose conversation over directive.

    Respond with valid JSON:
    {
        "intent": "directive|conversation|clarification",
        "action": {
            "action": "action_name",
            "content": "optional content",
            "phaseNumber": optional_number
        },
        "reasoning": "brief explanation"
    }

    For conversation intent, use:
    {
        "intent": "conversation",
        "action": {
            "action": "conversation",
            "content": "the user's message"
        },
        "reasoning": "why this is conversation"
    }

    For unclear/ambiguous commands, use:
    {
        "intent": "conversation",
        "action": {
            "action": "conversation",
            "content": "the user's message"
        },
        "reasoning": "unclear command, treating as conversation"
    }

    IMPORTANT: Never use "clarify" or "clarification" as an action - always route unclear requests as conversation.
    """

    init(groqApiKey: String) {
        self.groqApiKey = groqApiKey
    }

    func route(transcript: String) async throws -> RouterResponse {
        print("[Router] Routing transcript: \(transcript)")

        // Truncate very long transcripts to prevent token limit errors
        let truncatedTranscript = transcript.count > 1500
            ? String(transcript.prefix(1500)) + "..."
            : transcript

        // Create request
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let requestBody: [String: Any] = [
            "model": "moonshotai/kimi-k2-instruct-0905",  // Using Kimi K2
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": truncatedTranscript]
            ],
            "temperature": 0.1,
            "max_tokens": 400,  // Increased from 200 to handle longer responses
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("[Router] Sending request to Groq...")

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

        print("[Router] Raw response: \(content)")

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "Router", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse content"])
        }

        let routerResponse = try JSONDecoder().decode(RouterResponse.self, from: contentData)

        print("[Router] Parsed intent: \(routerResponse.intent), action: \(routerResponse.action)")

        return routerResponse
    }
}