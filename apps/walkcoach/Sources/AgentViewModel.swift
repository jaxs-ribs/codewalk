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

    private var audioTimer: Timer?
    private var recorder: Recorder?
    private var sttUploader: STTUploader?
    private var router: Router?
    private(set) var orchestrator: Orchestrator?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var currentRecordingURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init() {
        print("[WalkCoach] ViewModel initialized")
        setupServices()
    }

    private func setupServices() {
        // Initialize recorder immediately to pre-warm audio session
        recorder = Recorder()
        print("[WalkCoach] Recorder initialized and pre-warming audio session")

        // Load environment config
        let env = EnvConfig.load()

        sttUploader = STTUploader(groqApiKey: env.groqApiKey)
        print("[WalkCoach] STTUploader initialized")

        router = Router(groqApiKey: env.groqApiKey)
        print("[WalkCoach] Router initialized")

        orchestrator = Orchestrator(groqApiKey: env.groqApiKey)
        print("[WalkCoach] Orchestrator initialized")

        // Subscribe to orchestrator updates
        orchestrator?.$lastResponse
            .sink { [weak self] response in
                if !response.isEmpty {
                    self?.lastMessage = response
                }
            }
            .store(in: &cancellables)
    }

    func startRecording() {
        print("[WalkCoach] Starting recording")

        // Stop any ongoing TTS speech
        orchestrator?.stopSpeaking()

        currentState = .recording

        // Start recording instantly
        if recorder?.startInstant() == true {
            // Start monitoring audio levels
            audioTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                // For now, just use a random value since the API doesn't expose audio levels
                self?.audioLevel = Float.random(in: 0.1...0.5)
            }

            // Start recording timer
            recordingStartTime = Date()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let start = self?.recordingStartTime else { return }
                self?.recordingDuration = Date().timeIntervalSince(start)
            }
        } else {
            print("[WalkCoach] Failed to start recording")
            currentState = .idle
        }
    }

    func stopRecording() {
        print("[WalkCoach] Stopping recording")
        print("[WalkCoach] Recording duration: \(recordingDuration) seconds")

        // Stop the recording
        currentRecordingURL = recorder?.stop()

        // Stop monitoring
        audioTimer?.invalidate()
        audioTimer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        audioLevel = 0.0

        // Process the recording
        if let url = currentRecordingURL {
            print("[WalkCoach] Recording saved to: \(url.lastPathComponent)")
            currentState = .transcribing
            Task {
                await uploadAudio(url: url)
            }
        } else {
            print("[WalkCoach] WARNING: No recording URL returned")
            lastMessage = "Recording failed - no audio captured"
            currentState = .idle
        }
    }

    private func uploadAudio(url: URL) async {
        print("[WalkCoach] Uploading audio to Groq")

        // Check file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
            print("[WalkCoach] Audio file size: \(fileSize) bytes")
        }

        do {
            guard let uploader = sttUploader else {
                print("[WalkCoach] STTUploader is nil")
                await MainActor.run {
                    self.lastMessage = "Transcription service not configured"
                    self.currentState = .idle
                }
                return
            }

            // Upload audio and get transcription
            let result = try await uploader.transcribe(audioURL: url)

            await MainActor.run {
                self.transcription = result
                print("[WalkCoach] Transcription successful: \(result)")
            }

            // Route the transcript to determine intent
            await routeTranscript(result)
        } catch {
            print("[WalkCoach] Failed to upload audio: \(error)")
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
        print("[WalkCoach] Routing transcript: \(transcript)")

        // ALWAYS add to conversation history first
        await MainActor.run {
            self.orchestrator?.addUserTranscript(transcript)
        }

        do {
            guard let router = router else {
                print("[WalkCoach] Router not initialized")
                await MainActor.run {
                    self.lastMessage = "Router not configured"
                    self.currentState = .idle
                }
                return
            }

            let response = try await router.route(transcript: transcript)

            await MainActor.run {
                // Handle the routed action through orchestrator
                self.handleRoutedAction(response)
            }
        } catch {
            print("[WalkCoach] Routing failed: \(error)")

            // Even on routing failure, treat as conversation to maintain context
            await MainActor.run {
                // Enqueue as conversation so user's message is still processed
                self.orchestrator?.enqueueAction(.conversation(transcript))
                self.currentState = .idle
            }
        }
    }

    private func handleRoutedAction(_ response: RouterResponse) {
        print("[WalkCoach] Handling action: \(response.action)")

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