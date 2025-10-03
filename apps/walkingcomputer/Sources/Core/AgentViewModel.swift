import SwiftUI
import Combine
import AVFoundation

@MainActor
class AgentViewModel: ObservableObject {
    @Published var currentState: AgentState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var transcription: String = ""
    @Published var lastMessage: String = ""

    private var voiceInput: VoiceInputManager?
    private var voiceOutput: VoiceOutputManager?
    private var router: Router?
    private(set) var orchestrator: Orchestrator?
    private(set) var sessionManager: SessionManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        log("ViewModel initialized", category: .system)
        setupServices()
    }

    private func setupServices() {
        // Load environment config
        let env = EnvConfig.load()

        // Initialize session manager first
        sessionManager = SessionManager()
        sessionManager?.initialize()
        log("SessionManager initialized", category: .system)

        // Subscribe to session changes
        sessionManager?.$activeSessionId
            .dropFirst() // Skip initial value
            .sink { [weak self] newSessionId in
                guard let newSessionId = newSessionId else { return }
                self?.handleSessionSwitch(to: newSessionId)
            }
            .store(in: &cancellables)

        // Initialize voice I/O
        voiceInput = VoiceInputManager(groqApiKey: env.groqApiKey)
        voiceOutput = VoiceOutputManager(config: env)
        log("Voice I/O initialized", category: .system)

        router = Router(groqApiKey: env.groqApiKey, modelId: env.llmModelId)
        log("Router initialized", category: .system)

        // Initialize orchestrator with session manager
        if let sessionManager = sessionManager {
            orchestrator = Orchestrator(config: env, sessionManager: sessionManager, voiceOutput: voiceOutput)
            log("Orchestrator initialized", category: .system)
        }

        // Subscribe to orchestrator updates
        orchestrator?.$lastResponse
            .sink { [weak self] response in
                if !response.isEmpty {
                    self?.lastMessage = response
                }
            }
            .store(in: &cancellables)

        // Subscribe to voice input updates
        voiceInput?.$audioLevel
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        voiceInput?.$recordingDuration
            .sink { [weak self] duration in
                self?.recordingDuration = duration
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        log("🎙️ Starting recording...", category: .recorder)

        // Block recording only if writing/editing artifacts (allow interrupting reads and conversations)
        if orchestrator?.isExecuting == true,
           let currentAction = orchestrator?.currentAction,
           isWriteOrEditAction(currentAction) {
            log("⚠️ Blocked recording - writing/editing artifact in progress", category: .recorder)
            return
        }

        // Stop any ongoing TTS speech (for read actions)
        voiceOutput?.stop()

        currentState = .recording

        // Start recording
        if voiceInput?.startRecording() == true {
            log("Recording started", category: .recorder)
        } else {
            logError("Failed to start recording")
            currentState = .idle
        }
    }

    private func isWriteOrEditAction(_ action: ProposedAction) -> Bool {
        switch action {
        case .writeDescription, .writePhasing, .writeBoth,
             .editDescription, .editPhasing,
             .splitPhase, .mergePhases:
            return true
        default:
            return false
        }
    }

    func stopRecording() {
        log("Stopping recording", category: .recorder)

        // Stop the recording
        guard let url = voiceInput?.stopRecording() else {
            logError("No recording URL returned")
            lastMessage = "Recording failed - no audio captured"
            currentState = .idle
            return
        }

        log("Recording saved: \(url.lastPathComponent)", category: .recorder)
        currentState = .transcribing

        Task {
            await transcribeAndRoute(url: url)
        }
    }

    private func transcribeAndRoute(url: URL) async {
        do {
            guard let voiceInput = voiceInput else {
                logError("VoiceInputManager is nil")
                await MainActor.run {
                    self.lastMessage = "Voice input not configured"
                    self.currentState = .idle
                }
                return
            }

            let result = try await voiceInput.transcribe(audioURL: url)

            await MainActor.run {
                self.transcription = result
            }

            // Route the transcript to determine intent
            await routeTranscript(result)
        } catch {
            logError("Failed to transcribe audio: \(error)")
            await MainActor.run {
                let errorMessage = "Transcription failed - check GROQ_API_KEY"
                self.lastMessage = errorMessage
                self.currentState = .idle
            }
        }
    }

    func handleKeyDown() {
        switch currentState {
        case .idle:
            startRecording()
        default:
            break
        }
    }

    func handleKeyUp() {
        switch currentState {
        case .recording:
            stopRecording()
        default:
            break
        }
    }

    private func routeTranscript(_ transcript: String) async {
        log("Routing user intent...", category: .router)

        var routerContext = RouterContext.empty

        // Capture recent context, then record the new transcript
        await MainActor.run {
            if let orchestrator = self.orchestrator {
                let recentMessages = orchestrator.recentConversationContext(limit: 100)
                let lastSearchQuery = orchestrator.currentSearchQuery()
                orchestrator.addUserTranscript(transcript)
                routerContext = RouterContext(
                    recentMessages: recentMessages,
                    lastSearchQuery: lastSearchQuery
                )
            }
        }

        do {
            guard let router = router else {
                logError("Router not initialized")
                await MainActor.run {
                    self.lastMessage = "Router not configured"
                    self.currentState = .idle
                }
                return
            }

            let response = try await router.route(transcript: transcript, context: routerContext)

            await MainActor.run {
                // Handle the routed action through orchestrator
                self.handleRoutedAction(response)
            }
        } catch {
            logError("Routing failed: \(error)", component: "Router")

            // Even on routing failure, treat as conversation to maintain context
            await MainActor.run {
                // Enqueue as conversation so user's message is still processed
                self.orchestrator?.enqueueAction(.conversation(transcript))
                self.currentState = .idle
            }
        }
    }

    private func handleRoutedAction(_ response: RouterResponse) {
        log("Handling action: \(response.action)", category: .orchestrator)

        // Check if orchestrator is busy
        guard let orchestrator = orchestrator else {
            lastMessage = "Orchestrator not initialized"
            currentState = .idle
            return
        }

        if orchestrator.isExecuting {
            lastMessage = "Still processing..."
            currentState = .idle
            return
        }

        // Enqueue the action for execution
        orchestrator.enqueueAction(response.action)

        // Return to idle state (orchestrator updates will come via subscription)
        currentState = .idle
    }

    private func handleSessionSwitch(to newSessionId: UUID) {
        guard let sessionManager = sessionManager else {
            logError("Cannot handle session switch: no session manager", component: "AgentViewModel")
            return
        }

        log("Session switched to \(newSessionId) - recreating orchestrator", category: .system)

        // Verify the session manager has the new session ID
        if let currentId = sessionManager.getActiveSessionId() {
            log("SessionManager activeSessionId: \(currentId)", category: .system)
            if currentId != newSessionId {
                logError("⚠️ RACE CONDITION DETECTED! Publisher says \(newSessionId) but SessionManager still has \(currentId)", component: "AgentViewModel")
                logError("⚠️ Waiting briefly for SessionManager to update...", component: "AgentViewModel")

                // Wait for next run loop to let the assignment complete
                DispatchQueue.main.async { [weak self] in
                    self?.recreateOrchestrator(for: newSessionId)
                }
                return
            }
        }

        // Session ID matches, proceed
        recreateOrchestrator(for: newSessionId)
    }

    private func recreateOrchestrator(for sessionId: UUID) {
        guard let sessionManager = sessionManager else { return }

        log("Creating orchestrator for session: \(sessionId)", category: .system)

        // Stop any ongoing speech
        voiceOutput?.stop()

        // Recreate orchestrator with new session
        let env = EnvConfig.load()
        orchestrator = Orchestrator(config: env, sessionManager: sessionManager, voiceOutput: voiceOutput)

        // Re-subscribe to orchestrator updates
        orchestrator?.$lastResponse
            .sink { [weak self] response in
                if !response.isEmpty {
                    self?.lastMessage = response
                }
            }
            .store(in: &cancellables)

        log("Orchestrator recreated for session: \(sessionId)", category: .system)
    }
}
