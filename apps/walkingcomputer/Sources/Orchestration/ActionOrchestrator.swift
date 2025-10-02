import Foundation
import Combine

/// Orchestrates action execution through handlers
@MainActor
class ActionOrchestrator: ObservableObject {
    @Published var isExecuting: Bool = false
    @Published var lastResponse: String = ""

    private var actionQueue: [ActionQueueItem] = []
    private let handlers: [ActionHandler]

    // Context
    let conversationContext: ConversationContext
    let searchContext: SearchContext

    init(handlers: [ActionHandler], conversationContext: ConversationContext, searchContext: SearchContext) {
        self.handlers = handlers
        self.conversationContext = conversationContext
        self.searchContext = searchContext
    }

    // MARK: - Queue Management

    func enqueueAction(_ action: ProposedAction) {
        log("Enqueueing action: \(action)", category: .orchestrator)

        let item = ActionQueueItem(action: action)
        actionQueue.append(item)

        // Process queue if not already executing
        if !isExecuting {
            Task {
                await processQueue()
            }
        }
    }

    // MARK: - Test Mode Support

    /// Inject a text prompt directly, bypassing STT. For testing only.
    func injectPrompt(_ text: String, router: Router) async {
        log("Test mode: injecting prompt: \(text)", category: .orchestrator)

        // Add to conversation history as user input
        conversationContext.addUserMessage(text)

        // Route the prompt through the router (like production)
        do {
            let recentMessages = conversationContext.recentMessages(limit: 10)
            let context = RouterContext(recentMessages: recentMessages, lastSearchQuery: searchContext.lastQuery)
            let response = try await router.route(transcript: text, context: context)

            // Enqueue the routed action
            enqueueAction(response.action)

            // Wait for completion
            await waitForCompletion()
        } catch {
            logError("Test mode: Router failed: \(error)", component: "ActionOrchestrator")
            lastResponse = "Routing failed: \(error.localizedDescription)"
        }
    }

    /// Wait for orchestrator to finish all queued actions
    func waitForCompletion() async {
        while isExecuting || !actionQueue.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }

    private func processQueue() async {
        guard !actionQueue.isEmpty, !isExecuting else { return }

        log("Processing queue with \(actionQueue.count) items", category: .orchestrator)

        // Set executing flag
        isExecuting = true

        while !actionQueue.isEmpty {
            let item = actionQueue.removeFirst()
            await executeAction(item.action)
        }

        // Clear executing flag
        isExecuting = false
    }

    // MARK: - Action Execution

    private func executeAction(_ action: ProposedAction) async {
        log("Executing action: \(action)", category: .orchestrator)

        // Find handler that can handle this action
        guard let handler = handlers.first(where: { $0.canHandle(action) }) else {
            logError("No handler found for action: \(action)", component: "ActionOrchestrator")
            return
        }

        // Execute the action
        await handler.handle(action)

        // Update lastResponse from handler
        if let artifactHandler = handler as? ArtifactActionHandler {
            lastResponse = artifactHandler.lastResponse
        } else if let searchHandler = handler as? SearchActionHandler {
            lastResponse = searchHandler.lastResponse
        } else if let conversationHandler = handler as? ConversationActionHandler {
            lastResponse = conversationHandler.lastResponse
        }
    }

    // MARK: - Context Access (for compatibility)

    func recentConversationContext(limit: Int = 6) -> [String] {
        return conversationContext.recentMessages(limit: limit)
    }

    func currentSearchQuery() -> String? {
        return searchContext.lastQuery
    }

    func addUserTranscript(_ transcript: String) {
        conversationContext.addUserMessage(transcript)
    }
}

// MARK: - Action Queue Item

struct ActionQueueItem {
    let action: ProposedAction
    let id = UUID()
}
