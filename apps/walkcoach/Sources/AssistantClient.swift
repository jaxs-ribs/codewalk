import Foundation

// MARK: - Assistant Client

class AssistantClient {
    private let groqApiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    // Constants
    private let maxTokens = 2000
    private let temperature = 0.7
    private let conversationHistoryLimit = 100
    private let modelName = "moonshotai/kimi-k2-instruct-0905"

    init(groqApiKey: String) {
        self.groqApiKey = groqApiKey
        // print("[AssistantClient] Initialized")
    }

    // MARK: - Content Generation

    func generateDescription(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating description from conversation context")

        let systemPrompt = """
        You are synthesizing a project description from an EXTENSIVE conversation where the user has been thinking out loud.

        CRITICAL: You MUST generate the actual markdown document content, NOT a conversational response.

        CRITICAL CONTEXT RULES:
        - Review the ENTIRE conversation history, not just recent messages
        - The user has been adding ideas over many turns (possibly 30-40+)
        - Incorporate ALL features and requirements mentioned throughout
        - If something was mentioned early and refined later, use the refined version
        - This is a SYNTHESIS of everything discussed, not a summary of the last few messages

        CRITICAL TTS RULES:
        - Write like you're explaining to a friend on a walk
        - Use simple, clear sentences that flow naturally when spoken
        - Avoid parentheses, dashes, or complex punctuation
        - No bullet points or lists - use flowing prose instead
        - Keep sentences short enough to be said in one breath
        - Use "we're" instead of "we are", "it's" instead of "it is"
        - Add natural transitions like "so", "basically", "now"

        The description should be:
        - COMPREHENSIVE: Aim for 1500-2500 characters (not words, characters)
        - Include EVERY feature, requirement, and detail mentioned in the conversation
        - Start with WHAT it is, expand on HOW it works in detail, explain WHY it's useful
        - This will be THE specification document that guides implementation
        - Natural and conversational, but thorough - like giving a complete project brief on a walk
        - Don't leave out ANY details the user mentioned, even small ones

        Format:
        # Project Description

        [Your natural, speakable description here]
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Generate the complete description markdown document based on our conversation. Start with '# Project Description' and include all details discussed.")

        return try await callGroq(messages: messages)
    }

    func generatePhasing(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating phasing from conversation context")

        let systemPrompt = """
        You are synthesizing a project phasing plan from an EXTENSIVE conversation where the user has been thinking out loud.

        CRITICAL: You MUST generate the actual markdown document content, NOT a conversational response.

        CRITICAL CONTEXT RULES:
        - Review the ENTIRE conversation history (possibly 30-40+ exchanges)
        - Extract ALL technical requirements and features mentioned
        - Group related features into logical phases
        - If the user mentioned specific ordering or dependencies, respect them
        - This is a comprehensive plan based on EVERYTHING discussed

        CRITICAL TTS RULES:
        - Write like you're explaining the plan to a friend on a walk
        - Each phase gets one flowing paragraph, not bullet points
        - Start phases with transitions like "So first", "Then", "After that"
        - Keep sentences short and natural
        - Use contractions: we'll, you'll, it'll
        - Avoid technical jargon unless necessary

        The phasing should be:
        - COMPREHENSIVE: Aim for 2000-3000 characters total (not words, characters)
        - 3-5 phases that cover EVERYTHING mentioned in the conversation
        - Each phase has a short, clear title (3-5 words max)
        - Each phase has ONE DETAILED paragraph (200-400 chars) explaining exactly what we'll do
        - Include specific technical details, libraries, approaches discussed
        - CRITICAL: Each phase MUST end with a clear, testable deliverable
        - Example: "When this phase is done, you'll be able to tap record and see the waveform animate"
        - The deliverable should be something the user can actually verify works
        - This is THE implementation roadmap - be thorough and specific

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
                                    userPrompt: "Generate the complete phasing plan markdown document based on our conversation. Start with '# Project Phasing' and include all phases.")

        return try await callGroq(messages: messages)
    }

    func generateConversationalResponse(conversationHistory: [(role: String, content: String)]) async throws -> String {
        print("[AssistantClient] Generating conversational response")

        let systemPrompt = """
        You are a passive note-taker for a voice-first project speccer. Your primary role is to LISTEN and ACKNOWLEDGE.

        CRITICAL BEHAVIOR RULES:

        1. STATEMENTS (user shares ideas/features/requirements):
           - Respond with ONLY: "Noted"
           - NEVER elaborate or suggest unless explicitly asked
           - Examples: "I want it to have blue buttons" → "Noted"

        2. TECHNICAL QUESTIONS (what technology/how to implement/architecture):
           - Give a brief 2-3 sentence technical answer
           - Be specific and actionable
           - Examples: "What database should I use?" → "For this app, PostgreSQL would work well for relational data. MongoDB if you need flexible schemas."

        3. YES/NO QUESTIONS (should I/would it be good/is it possible):
           - Start with clear yes/no, then ONE clarifying sentence
           - Examples: "Should I use TypeScript?" → "Yes, TypeScript would help catch errors early in a complex app like this."

        4. BRAINSTORMING REQUESTS (can you suggest/give me ideas/what features):
           - Provide exactly 2-3 concrete suggestions
           - Keep each to one sentence
           - Examples: "What features could we add?" → "You could add user profiles, a recommendation engine, or offline mode support."

        Remember: You're a SINK for ideas. Default to brief acknowledgments unless directly asked a question.
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