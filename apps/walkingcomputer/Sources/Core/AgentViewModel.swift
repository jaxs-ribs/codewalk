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
    private(set) var orchestrator: Orchestrator?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var currentRecordingURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init() {
        log("ViewModel initialized", category: .system)
        setupServices()
    }

    private func setupServices() {
        // Initialize recorder immediately to pre-warm audio session
        recorder = Recorder()
        log("Recorder initialized and pre-warming audio session", category: .system)

        // Load environment config
        let env = EnvConfig.load()

        // Initialize STT
        sttUploader = STTUploader(groqApiKey: env.groqApiKey)
        log("Using Groq STT for transcription", category: .system)

        orchestrator = Orchestrator(config: env)
        log("Orchestrator initialized", category: .system)

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
        log("🎙️ Starting recording...", category: .recorder)

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
            logError("Failed to start recording")
            currentState = .idle
        }
    }

    func stopRecording() {
        log("Stopping recording", category: .recorder)
        log(String(format: "Recording duration: %.2f seconds", recordingDuration), category: .recorder)

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
            log("Recording saved: \(url.lastPathComponent)", category: .recorder)
            currentState = .transcribing
            Task {
                await uploadAudio(url: url)
            }
        } else {
            logError("No recording URL returned")
            lastMessage = "Recording failed - no audio captured"
            currentState = .idle
        }
    }

    private func uploadAudio(url: URL) async {
        log("Uploading audio to Groq API...", category: .network)

        // Check file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
            log("Audio file size: \(fileSize) bytes", category: .network)
        }

        do {
            guard let uploader = sttUploader else {
                logError("STTUploader is nil")
                await MainActor.run {
                    self.lastMessage = "Groq transcription service not configured"
                    self.currentState = .idle
                }
                return
            }

            let result = try await uploader.transcribe(audioURL: url)

            await MainActor.run {
                self.transcription = result
                logSuccess("Transcription successful", component: "Groq")
                // Log full user transcript in beautiful format
                logUserTranscript(result)
            }

            // Route the transcript to determine intent
            await routeTranscript(result)
        } catch {
            logError("Failed to upload audio: \(error)")
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
        // Delegate routing to orchestrator - it has the router with registry
        await MainActor.run {
            orchestrator?.routeAndEnqueue(transcript: transcript)
            self.currentState = .idle
        }
    }
}
