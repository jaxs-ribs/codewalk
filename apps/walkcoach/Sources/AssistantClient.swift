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
        You are a voice-first project speccer optimized for text-to-speech while walking.

        CRITICAL TTS RULES:
        - Write like you're explaining to a friend on a walk
        - Use simple, clear sentences that flow naturally when spoken
        - Avoid parentheses, dashes, or complex punctuation
        - No bullet points or lists - use flowing prose instead
        - Keep sentences short enough to be said in one breath
        - Use "we're" instead of "we are", "it's" instead of "it is"
        - Add natural transitions like "so", "basically", "now"

        The description should be:
        - About 3-5 sentences explaining what we're building
        - Start with WHAT it is, then HOW it works, then WHY it's useful
        - Focused on the core functionality, not implementation details
        - Natural and conversational, like explaining to a friend on a walk

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
        You are a voice-first project speccer optimized for text-to-speech while walking.

        CRITICAL TTS RULES:
        - Write like you're explaining the plan to a friend on a walk
        - Each phase gets one flowing paragraph, not bullet points
        - Start phases with transitions like "So first", "Then", "After that"
        - Keep sentences short and natural
        - Use contractions: we'll, you'll, it'll
        - Avoid technical jargon unless necessary

        The phasing should be:
        - 3-5 phases for most projects
        - Each phase has a short, clear title (3-5 words max)
        - Each phase has ONE paragraph explaining what we'll do
        - CRITICAL: Each phase MUST end with a clear, testable deliverable
        - Example: "When this phase is done, you'll be able to tap record and see the waveform animate"
        - The deliverable should be something the user can actually verify works

        Format:
        # Project Phasing

        ## Phase 1: [Short Clear Title]
        [One flowing paragraph starting with "So" or "First" that explains this phase naturally. MUST end with: "When this phase is done, you'll be able to [specific testable action]"]

        ## Phase 2: [Short Clear Title]
        [One flowing paragraph starting with "Then" or "Next" that explains this phase naturally. MUST end with: "Once complete, you can test by [specific verification step]"]

        (Continue as needed - EVERY phase needs a testable deliverable)
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
            "model": "moonshotai/kimi-k2-instruct-0905",
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 800
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("[AssistantClient] Sending request to Groq...")

        // Use retry logic for resilience
        let data = try await NetworkManager.shared.performRequestWithRetry(request)

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