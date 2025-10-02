import Foundation

/// Low-level Groq API client - handles HTTP communication only
class GroqLLMClient {
    private let apiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Generate completion from messages
    func generate(
        messages: [[String: String]],
        model: String,
        temperature: Double = 0.7,
        maxTokens: Int = 2000,
        responseFormat: [String: String]? = nil
    ) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        if let format = responseFormat {
            requestBody["response_format"] = format
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        log("Sending request to Groq...", category: .network, component: "GroqLLMClient")

        // Use retry logic for resilience
        let data = try await NetworkManager.shared.performRequestWithRetry(request)

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "GroqLLMClient", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        log("Generated \(content.count) chars", category: .network, component: "GroqLLMClient")
        return content
    }
}
