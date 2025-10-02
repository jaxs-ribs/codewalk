import Foundation

/// Handles conversational responses
class ConversationActionHandler: ActionHandler {
    private let assistantClient: AssistantClient
    private let voiceOutput: VoiceOutputManager
    private let conversationContext: ConversationContext
    private let searchContext: SearchContext
    var lastResponse: String = ""

    init(
        assistantClient: AssistantClient,
        voiceOutput: VoiceOutputManager,
        conversationContext: ConversationContext,
        searchContext: SearchContext
    ) {
        self.assistantClient = assistantClient
        self.voiceOutput = voiceOutput
        self.conversationContext = conversationContext
        self.searchContext = searchContext
    }

    func canHandle(_ action: ProposedAction) -> Bool {
        switch action {
        case .conversation:
            return true
        default:
            return false
        }
    }

    func handle(_ action: ProposedAction) async {
        switch action {
        case .conversation(let content):
            await handleConversation(content)
        default:
            break
        }
    }

    // MARK: - Conversation Handling

    private func handleConversation(_ content: String) async {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerContent = trimmedContent.lowercased()

        if let explicitQuery = extractSearchQuery(from: trimmedContent) {
            log("Detected inline search request: '\(explicitQuery)'", category: .search, component: "ConversationActionHandler")
            // Note: We don't execute search here - that's handled by SearchActionHandler
            // This is just for logging/detection
            return
        }

        do {
            // Generate conversational response
            let response = try await assistantClient.generateConversationalResponse(
                conversationHistory: conversationContext.allMessages()
            )

            lastResponse = response

            // Speak the response
            await speak(response)

            // Add assistant response to history
            conversationContext.addAssistantMessage(response)
        } catch {
            logError("Failed to generate response: \(error)", component: "ConversationActionHandler")
            lastResponse = "I couldn't process that. Try again?"

            // Speak the error
            await speak(lastResponse)
        }
    }

    private func extractSearchQuery(from content: String) -> String? {
        let patterns = [
            "search for",
            "look up",
            "find information about",
            "find info about",
            "find details about",
            "search the web for",
            "search the internet for",
            "can you search for",
            "please search for",
            "do a search for",
            "run a search for",
            "find out about"
        ]

        for pattern in patterns {
            if let range = content.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) {
                let queryStart = range.upperBound
                let rawQuery = content[queryStart...]
                let trimmedQuery = rawQuery
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,:;-"))

                if !trimmedQuery.isEmpty {
                    let lowerQuery = trimmedQuery.lowercased()
                    if !lowerQuery.hasPrefix("that") &&
                        !lowerQuery.hasPrefix("it") &&
                        !lowerQuery.hasPrefix("them") &&
                        !lowerQuery.hasPrefix("this") {
                        return trimmedQuery
                    }
                }
            }
        }

        return nil
    }

    private func speak(_ text: String) async {
        await voiceOutput.speak(text)
    }
}
