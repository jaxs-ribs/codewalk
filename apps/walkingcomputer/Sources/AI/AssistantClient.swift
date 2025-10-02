import Foundation

// MARK: - Assistant Client (Facade)

/// Facade that delegates to ContentGenerator for backward compatibility
class AssistantClient {
    private let contentGenerator: ContentGenerator

    init(groqApiKey: String, modelName: String) {
        let llmClient = GroqLLMClient(apiKey: groqApiKey)
        contentGenerator = ContentGenerator(llmClient: llmClient, modelName: modelName)
    }

    // MARK: - Content Generation

    func generateDescription(conversationHistory: [(role: String, content: String)]) async throws -> String {
        return try await contentGenerator.generateDescription(conversationHistory: conversationHistory)
    }

    func generatePhasing(conversationHistory: [(role: String, content: String)], statusCallback: ((String) -> Void)? = nil) async throws -> String {
        return try await contentGenerator.generatePhasing(conversationHistory: conversationHistory, statusCallback: statusCallback)
    }

    func generateConversationalResponse(conversationHistory: [(role: String, content: String)]) async throws -> String {
        return try await contentGenerator.generateConversationalResponse(conversationHistory: conversationHistory)
    }
}
