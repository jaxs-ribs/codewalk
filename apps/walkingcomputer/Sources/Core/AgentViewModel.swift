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
    private var cancellables = Set<AnyCancellable>()

    init() {
        log("ViewModel initialized", category: .system)
        setupServices()
    }

    private func setupServices() {
        // Load environment config
        let env = EnvConfig.load()

        // Initialize voice I/O
        voiceInput = VoiceInputManager(groqApiKey: env.groqApiKey)
        voiceOutput = VoiceOutputManager(config: env)
        log("Voice I/O initialized", category: .system)

        router = Router(groqApiKey: env.groqApiKey, modelId: env.llmModelId)
        log("Router initialized", category: .system)

        orchestrator = Orchestrator(config: env, voiceOutput: voiceOutput)
        log("Orchestrator initialized", category: .system)

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

        // Stop any ongoing TTS speech
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
}
