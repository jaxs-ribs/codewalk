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
            currentState = .transcribing
            Task {
                await uploadAudio(url: url)
            }
        } else {
            currentState = .idle
        }
    }

    private func uploadAudio(url: URL) async {
        print("[WalkCoach] Uploading audio to Groq")

        do {
            // Upload audio and get transcription
            let result = try await sttUploader?.transcribe(audioURL: url) ?? ""

            await MainActor.run {
                self.transcription = result
                print("[WalkCoach] Transcription: \(result)")

                // For now, just display the transcription
                self.lastMessage = result

                // Return to idle state
                self.currentState = .idle
            }
        } catch {
            print("[WalkCoach] Failed to upload audio: \(error)")
            await MainActor.run {
                self.lastMessage = "Failed to transcribe"
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
}