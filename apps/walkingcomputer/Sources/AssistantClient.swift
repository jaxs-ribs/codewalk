import Foundation

// MARK: - Assistant Client

class AssistantClient {
    private let groqApiKey: String
    private let modelName: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    // Constants
    private let maxTokens = 2000
    private let temperature = 0.7
    private let conversationHistoryLimit = 100

    init(groqApiKey: String, modelName: String) {
        self.groqApiKey = groqApiKey
        self.modelName = modelName
        // print("[AssistantClient] Initialized")
    }

    // MARK: - Content Generation

    func generateDescription(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating description from conversation context")

        let systemPrompt = """
        Generate a project description from this conversation.

        CRITICAL: Generate the actual markdown document, NOT a conversational response.

        CONTEXT:
        - Review the ENTIRE conversation history
        - Synthesize features the user WANTS
        - Silently omit anything user rejected
        - This is THE specification document

        TTS OPTIMIZATION:
        - Write conversationally, like explaining to a friend
        - Use contractions (it's, we'll, don't)
        - Short, clear sentences
        - No bullets, flowing prose only
        - Natural transitions ("so", "basically")

        CONTENT:
        - Comprehensive but concise (1200-1800 characters)
        - Only describe what WILL be built
        - Never mention what won't be included
        - Be thorough but direct

        Format:
        # Project Description

        [Your natural, speakable description]
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Generate the complete description markdown document based on our conversation. Start with '# Project Description' and include all details discussed.")

        return try await callGroq(messages: messages)
    }

    func generatePhasing(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating phasing from conversation context")

        let systemPrompt = """
        Generate a project phasing plan from this conversation.

        CRITICAL: Generate the actual markdown document, NOT a conversational response.

        CONTEXT:
        - Extract features user WANTS from conversation
        - Silently exclude rejected features
        - Group into logical phases
        - This is THE implementation roadmap

        TTS OPTIMIZATION:
        - Each phase: one flowing paragraph
        - Use transitions: "So first", "Then", "After that"
        - Contractions always (we'll, it'll)
        - Natural, conversational tone

        CONTENT:
        - 3-5 phases covering accepted features only
        - Short titles (3-5 words)
        - Each phase: concise paragraph (150-250 chars)
        - Include specific technical details
        - Each phase MUST have "Definition of Done"

        Format:
        # Project Phasing

        ## Phase 1: [Short Title]
        [Flowing paragraph starting with "So first" or "First"]
        **Definition of Done:** [Concrete test with expected outcome]

        ## Phase 2: [Short Title]
        [Flowing paragraph starting with "Then" or "Next"]
        **Definition of Done:** [Concrete test with expected outcome]
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Generate the complete phasing plan markdown document based on our conversation. Start with '# Project Phasing' and include all phases.")

        return try await callGroq(messages: messages)
    }

    func generateConversationalResponse(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating conversational response")

        let systemPrompt = """
        You are a passive voice-first project speccer. LISTEN, don't help.

        YOUR CAPABILITIES:
        - You CAN search the web (say "search for X" to trigger it)
        - You're here to take notes about projects

        CRITICAL RULES:
        1. If user is TELLING you something (statements, ideas, features):
           ONLY respond "Noted" or "Got it" - NOTHING ELSE

        2. If user ASKS a direct question:
           - About weather/news/facts → "Say 'search for X' to look that up"
           - "Do you have suggestions?" → Give 2-3 flowing suggestions
           - Technical questions → One sentence answer
           - "Should I do X?" → "Yes" or "No" plus one sentence

        3. NEVER ask clarifying questions unless truly incomprehensible

        EXAMPLES:
        User: "I'm building a dog app" → "Got it"
        User: "What's the weather?" → "Say 'search for Stockholm weather' to look that up"
        User: "Do you have suggestions?" → "You could add profiles, or maybe chat"

        Default to acknowledgment. Only elaborate when directly asked.
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

        // Add full conversation history (up to limit for comprehensive context)
        let recentHistory = conversationHistory.suffix(conversationHistoryLimit)
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
            "model": modelName,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
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
