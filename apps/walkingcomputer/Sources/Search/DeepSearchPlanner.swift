import Foundation

// MARK: - Deep Search Models

struct SearchSubQuestion: Codable {
    let q: String  // The subquestion
    let why: String  // Why this subquestion matters
    let queries: [String]  // 2-4 literal search queries
    let domains: [String]?  // Optional domain hints
    let freshness_days: Int?  // Optional freshness requirement
}

struct SearchPlan: Codable {
    let goal: String
    let subqs: [SearchSubQuestion]
}

// MARK: - Deep Search Planner

class DeepSearchPlanner {
    private let groqApiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"
    private let modelId: String  // Will be configured from environment

    private let systemPrompt = """
    You are ResearchPlanner for a deep-search agent. Design the smallest plan that can answer the goal using web search.

    - Prefer primary/official sources; no answering.
    - Return ≤ 4 sub-questions; 2-4 literal queries each.
    - Include optional domain hints and freshness need if time-sensitive.

    Output (STRICT JSON only):
    {
        "goal": "<user goal>",
        "subqs": [
            {
                "q": "specific subquestion",
                "why": "why this matters for the goal",
                "queries": ["literal search query 1", "literal search query 2"],
                "domains": ["example.com", "official.org"],
                "freshness_days": null
            }
        ]
    }

    IMPORTANT:
    - Queries should be specific search strings, not questions
    - Use keywords that will return good search results
    - For technical topics, include official docs in domains
    - For news/current events, set freshness_days (e.g., 30 for last month)
    """

    init(groqApiKey: String, modelId: String? = nil) {
        self.groqApiKey = groqApiKey
        // Use provided model or default to the thinking model
        self.modelId = modelId ?? "openai/gpt-oss-120b"
    }

    func generatePlan(goal: String, context: [String]) async throws -> SearchPlan {
        log("[PLANNER] Starting plan generation for goal: '\(goal)'", category: .search)

        // Build the user prompt with context
        let userPrompt = buildUserPrompt(goal: goal, context: context)
        log("[PLANNER] User prompt length: \(userPrompt.count) chars", category: .search)

        // Create request
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let requestBody: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.2,  // Low temperature for consistent structure
            "max_tokens": 800,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        log("[PLANNER] Sending request to Groq API (model: \(modelId))", category: .search)

        // Perform request
        let startTime = Date()
        let data = try await NetworkManager.shared.performRequestWithRetry(request)
        let planningTime = Date().timeIntervalSince(startTime)

        log("[PLANNER] Response received in \(String(format: "%.2f", planningTime))s", category: .search)

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "DeepSearchPlanner", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response format from LLM"])
        }

        log("[PLANNER] Raw LLM response: \(content)", category: .search)

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "DeepSearchPlanner", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert response to data"])
        }

        do {
            let plan = try JSONDecoder().decode(SearchPlan.self, from: contentData)

            // Log the parsed plan
            log("[PLANNER] Generated plan:", category: .search)
            log("[PLANNER] Goal: \(plan.goal)", category: .search)
            log("[PLANNER] Subquestions: \(plan.subqs.count)", category: .search)

            for (index, subq) in plan.subqs.enumerated() {
                log("[PLANNER] Subq \(index + 1): \(subq.q)", category: .search)
                log("[PLANNER]   Why: \(subq.why)", category: .search)
                log("[PLANNER]   Queries: \(subq.queries.joined(separator: ", "))", category: .search)
                if let domains = subq.domains {
                    log("[PLANNER]   Domains: \(domains.joined(separator: ", "))", category: .search)
                }
                if let freshness = subq.freshness_days {
                    log("[PLANNER]   Freshness: \(freshness) days", category: .search)
                }
            }

            return plan
        } catch {
            log("[PLANNER] Failed to parse JSON: \(error)", category: .search)
            log("[PLANNER] Content was: \(content)", category: .search)

            // Try to provide more specific error info
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    log("[PLANNER] Missing key: \(key.stringValue) at \(context.codingPath)", category: .search)
                case .typeMismatch(let type, let context):
                    log("[PLANNER] Type mismatch: expected \(type) at \(context.codingPath)", category: .search)
                case .valueNotFound(let type, let context):
                    log("[PLANNER] Value not found: \(type) at \(context.codingPath)", category: .search)
                case .dataCorrupted(let context):
                    log("[PLANNER] Data corrupted at \(context.codingPath): \(context.debugDescription)", category: .search)
                @unknown default:
                    log("[PLANNER] Unknown decoding error", category: .search)
                }
            }

            throw NSError(domain: "DeepSearchPlanner", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse plan JSON: \(error.localizedDescription)"])
        }
    }

    private func buildUserPrompt(goal: String, context: [String]) -> String {
        var sections: [String] = []

        if !context.isEmpty {
            // Take only recent context to avoid token limits
            let recentContext = context.suffix(5).joined(separator: "\n")
            sections.append("Recent conversation context:\n\(recentContext)")
        }

        sections.append("User's search goal: \(goal)")
        sections.append("Generate a search plan with specific, literal search queries that will find relevant information.")

        return sections.joined(separator: "\n\n")
    }
}