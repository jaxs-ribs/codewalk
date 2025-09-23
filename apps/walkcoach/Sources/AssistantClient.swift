import Foundation

// MARK: - Assistant Client

class AssistantClient {
    private let groqApiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    init(groqApiKey: String) {
        self.groqApiKey = groqApiKey
        print("[AssistantClient] Initialized")
    }

    // MARK: - Content Generation

    func generateDescription(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating description from conversation context")

        let systemPrompt = """
        You are a voice-first project speccer. Generate a project description based on the conversation.

        The description should be:
        - Written for reading aloud while walking (TTS-optimized)
        - Clear and conversational, not formal documentation
        - Focused on what the project does and why it matters
        - About 3-5 sentences that flow naturally when spoken
        - Free of markdown formatting except for the title

        Format:
        # Project Description

        [Your natural, speakable description here]
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Based on our conversation, write a clear project description that sounds good when read aloud.")

        return try await callGroq(messages: messages)
    }

    func generatePhasing(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating phasing from conversation context")

        let systemPrompt = """
        You are a voice-first project speccer. Generate a phasing plan based on the conversation.

        The phasing should be:
        - Written for reading aloud while walking (TTS-optimized)
        - Each phase should have a clear title and a single paragraph description
        - The paragraph should be conversational, like explaining to a friend
        - Typically 3-5 phases, but adjust based on project complexity
        - Free of bullet points or complex formatting

        Format:
        # Project Phasing

        ## Phase 1: [Clear Title]
        [One paragraph explaining what happens in this phase, written naturally for speech]

        ## Phase 2: [Clear Title]
        [One paragraph explaining what happens in this phase, written naturally for speech]

        (Continue as needed)
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Based on our conversation, create a phasing plan that sounds natural when read aloud.")

        return try await callGroq(messages: messages)
    }

    func generateConversationalResponse(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating conversational response")

        let systemPrompt = """
        You are a voice-first project speccer assistant. Respond naturally and conversationally.
        Keep responses brief (1-3 sentences) and suitable for text-to-speech.
        You're helping someone spec out their project while they walk.
        """

        // Use the last user message as the prompt
        let lastUserMessage = conversationHistory.last { $0.role == "user" }?.content ?? ""

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: Array(conversationHistory.dropLast()),
                                    userPrompt: lastUserMessage)

        return try await callGroq(messages: messages)
    }

    // MARK: - Helper Methods

    private func buildMessages(systemPrompt: String,
                              conversationHistory: [(role: String, content: String)],
                              userPrompt: String) -> [[String: String]] {

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add conversation history (last 10 exchanges)
        let recentHistory = conversationHistory.suffix(20)
        for exchange in recentHistory {
            messages.append(["role": exchange.role, "content": exchange.content])
        }

        // Add the specific request
        messages.append(["role": "user", "content": userPrompt])

        return messages
    }

    private func callGroq(messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "llama-3.3-70b-versatile",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 800
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("[AssistantClient] Sending request to Groq...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AssistantClient", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AssistantClient] API Error (\(httpResponse.statusCode)): \(errorBody)")
            throw NSError(domain: "AssistantClient", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: errorBody])
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AssistantClient", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        print("[AssistantClient] Generated \(content.count) chars")
        return content
    }
}