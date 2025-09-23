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
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var currentRecordingURL: URL?

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
    }

    func startRecording() {
        print("[WalkCoach] Starting recording")
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
                // Handle the routed action
                self.handleRoutedAction(response)
            }
        } catch {
            print("[WalkCoach] Routing failed: \(error)")
            await MainActor.run {
                self.lastMessage = "Failed to understand command"
                self.currentState = .idle
            }
        }
    }

    private func handleRoutedAction(_ response: RouterResponse) {
        print("[WalkCoach] Handling action: \(response.action)")

        switch response.action {
        case .writeDescription:
            lastMessage = "Would write description (Phase 4+ needed)"
        case .writePhasing:
            lastMessage = "Would write phasing (Phase 4+ needed)"
        case .readDescription:
            lastMessage = "Would read description (Phase 5+ needed)"
        case .readPhasing:
            lastMessage = "Would read phasing (Phase 5+ needed)"
        case .editDescription(let content):
            lastMessage = "Would edit description: \(content)"
        case .editPhasing(let phase, let content):
            if let phase = phase {
                lastMessage = "Would edit phase \(phase): \(content)"
            } else {
                lastMessage = "Would edit phasing: \(content)"
            }
        case .conversation(let content):
            lastMessage = "Conversation: \(content)"
        case .clarification(let question):
            lastMessage = "Need clarification: \(question)"
        case .repeatLast:
            lastMessage = "Would repeat last response"
        case .nextPhase:
            lastMessage = "Would go to next phase"
        case .previousPhase:
            lastMessage = "Would go to previous phase"
        case .stop:
            lastMessage = "Stopping"
        }

        // Return to idle state
        currentState = .idle
    }
}