import Foundation

// MARK: - Perplexity Search Errors

enum PerplexitySearchError: LocalizedError {
    case invalidResponse
    case rateLimitExceeded(String)
    case apiError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Perplexity API"
        case .rateLimitExceeded(let message):
            return message
        case .apiError(let code, let message):
            return "\(message): \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Perplexity Service

class PerplexitySearchService {
    private let apiKey: String
    private let apiURL = "https://api.perplexity.ai/chat/completions"

    private let systemPrompt = """
    TTS search summarizer. Be extremely concise.

    RULES:
    - Maximum 2-3 sentences for shallow search
    - Maximum 4-5 sentences for deep research
    - NO citations, URLs, or source names
    - NO thinking tags or internal monologue
    - Simple spoken English only
    - Direct answer, then stop
    """

    init(apiKey: String) {
        self.apiKey = apiKey
        log("Initialized with API key: \(apiKey.prefix(10))...", category: .search, component: "PerplexitySearchService")
    }

    // MARK: - Public Interface

    func search(query: String, depth: SearchDepth = .small) async throws -> String {
        log("Starting \(depth.rawValue) search for: \(query)", category: .search, component: "PerplexitySearchService")
        let startTime = Date()

        // Build request
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build payload
        let payload: [String: Any] = [
            "model": depth.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": query]
            ],
            "stream": true,
            "temperature": 0.2,
            "max_output_tokens": depth.maxOutputTokens,
            "web_search_options": [
                "search_context_size": depth.searchContextSize
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // Stream response
        let response = try await streamChatCompletion(request: request)

        let elapsed = Date().timeIntervalSince(startTime)
        log("Perplexity \(depth.rawValue) search completed in \(String(format: "%.2f", elapsed))s", category: .search, component: "PerplexitySearchService")

        return response
    }

    // MARK: - Streaming

    private func streamChatCompletion(request: URLRequest) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PerplexitySearchError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw PerplexitySearchError.rateLimitExceeded("Perplexity API rate limit reached. Please wait a moment.")
        }

        guard httpResponse.statusCode == 200 else {
            // Try to get error message
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody.append(line)
                if errorBody.count > 1000 { break }
            }
            logError("API Error \(httpResponse.statusCode): \(errorBody)", component: "PerplexitySearchService")
            throw PerplexitySearchError.apiError(httpResponse.statusCode, "Perplexity API error")
        }

        var result = ""

        // Process line by line instead of byte by byte
        for try await line in asyncBytes.lines {
            // Skip empty lines
            if line.isEmpty { continue }

            // Process SSE data lines
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))

                // Check for end of stream
                if data == "[DONE]" {
                    break
                }

                // Parse JSON and extract content
                if let jsonData = data.data(using: .utf8) {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let delta = firstChoice["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            result.append(content)
                        }
                    } catch {
                        logError("Failed to parse JSON: \(error), data: \(data)", component: "PerplexitySearchService")
                    }
                }
            }
        }

        log("Final result length: \(result.count) chars", category: .search, component: "PerplexitySearchService")
        return result
    }
}