import Foundation
import Combine

// MARK: - Orchestrator (Facade)

/// Facade that delegates to ActionOrchestrator for backward compatibility
@MainActor
class Orchestrator: ObservableObject {
    @Published var isExecuting: Bool = false
    @Published var lastResponse: String = ""

    private let actionOrchestrator: ActionOrchestrator
    private let voiceOutput: VoiceOutputManager
    private let sessionManager: SessionManager
    private var cancellables = Set<AnyCancellable>()

    init(config: EnvConfig, sessionManager: SessionManager, voiceOutput: VoiceOutputManager? = nil) {
        self.sessionManager = sessionManager

        // Use provided voice output or create new one
        if let provided = voiceOutput {
            self.voiceOutput = provided
        } else {
            self.voiceOutput = VoiceOutputManager(config: config)
        }

        // Get conversation context from session manager
        let conversationContext = sessionManager.conversationContext
        let searchContext = SearchContext()

        // Initialize services with active session ID
        let activeSessionId = sessionManager.getActiveSessionId()
        log("Orchestrator initializing with session ID: \(activeSessionId?.uuidString ?? "nil")", category: .system, component: "Orchestrator")
        let artifactManager = ArtifactManager(groqApiKey: config.groqApiKey, sessionId: activeSessionId)
        let assistantClient = AssistantClient(groqApiKey: config.groqApiKey, modelName: config.llmModelId)

        // Initialize search services
        var perplexityService: PerplexitySearchService? = nil
        var braveService: SearchService? = nil

        if !config.perplexityApiKey.isEmpty {
            perplexityService = PerplexitySearchService(apiKey: config.perplexityApiKey)
            log("PerplexitySearchService initialized", category: .system, component: "Orchestrator")
        } else if !config.braveApiKey.isEmpty {
            braveService = SearchService(config: config)
            log("SearchService (Brave) initialized as fallback", category: .system, component: "Orchestrator")
        }

        // Initialize handlers
        let artifactHandler = ArtifactActionHandler(
            artifactManager: artifactManager,
            assistantClient: assistantClient,
            voiceOutput: self.voiceOutput,
            conversationContext: conversationContext
        )

        let searchHandler = SearchActionHandler(
            perplexityService: perplexityService,
            braveService: braveService,
            voiceOutput: self.voiceOutput,
            conversationContext: conversationContext,
            searchContext: searchContext
        )

        let conversationHandler = ConversationActionHandler(
            assistantClient: assistantClient,
            voiceOutput: self.voiceOutput,
            conversationContext: conversationContext,
            searchContext: searchContext
        )

        let handlers: [ActionHandler] = [artifactHandler, searchHandler, conversationHandler]

        // Initialize action orchestrator
        actionOrchestrator = ActionOrchestrator(
            handlers: handlers,
            conversationContext: conversationContext,
            searchContext: searchContext
        )

        log("Initialized with ActionOrchestrator and handlers", category: .system, component: "Orchestrator")

        // Subscribe to actionOrchestrator updates
        actionOrchestrator.$lastResponse
            .sink { [weak self] response in
                self?.lastResponse = response
                // Auto-save conversation after each response
                self?.sessionManager.saveCurrentConversation()
            }
            .store(in: &cancellables)

        actionOrchestrator.$isExecuting
            .sink { [weak self] executing in
                self?.isExecuting = executing
            }
            .store(in: &cancellables)
    }

    // MARK: - Delegated Methods

    func enqueueAction(_ action: ProposedAction) {
        actionOrchestrator.enqueueAction(action)
    }

    func injectPrompt(_ text: String) async {
        // Need to create a router for test mode
        let config = EnvConfig.load()
        let router = Router(groqApiKey: config.groqApiKey, modelId: config.llmModelId)
        await actionOrchestrator.injectPrompt(text, router: router)
    }

    func waitForCompletion() async {
        await actionOrchestrator.waitForCompletion()
    }

    func recentConversationContext(limit: Int = 6) -> [String] {
        return actionOrchestrator.recentConversationContext(limit: limit)
    }

    func currentSearchQuery() -> String? {
        return actionOrchestrator.currentSearchQuery()
    }

    func addUserTranscript(_ transcript: String) {
        actionOrchestrator.addUserTranscript(transcript)
    }

    func stopSpeaking() {
        voiceOutput.stop()
    }
}
