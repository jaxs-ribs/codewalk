import Foundation
import AVFoundation

/// Manages voice input: recording and transcription
@MainActor
class VoiceInputManager: ObservableObject {
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0

    private var recorder: Recorder?
    private var sttUploader: STTUploader?
    private var audioTimer: Timer?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var currentRecordingURL: URL?

    init(groqApiKey: String) {
        // Initialize recorder immediately to pre-warm audio session
        recorder = Recorder()
        log("Recorder initialized and pre-warming audio session", category: .system)

        // Initialize STT
        sttUploader = STTUploader(groqApiKey: groqApiKey)
        log("Using Groq STT for transcription", category: .system)
    }

    func startRecording() -> Bool {
        log("🎙️ Starting recording...", category: .recorder)

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

            return true
        } else {
            logError("Failed to start recording")
            return false
        }
    }

    func stopRecording() -> URL? {
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

        if let url = currentRecordingURL {
            log("Recording saved: \(url.lastPathComponent)", category: .recorder)
            return url
        } else {
            logError("No recording URL returned")
            return nil
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        log("Uploading audio to Groq API...", category: .network)

        // Check file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int {
            log("Audio file size: \(fileSize) bytes", category: .network)
        }

        guard let uploader = sttUploader else {
            throw NSError(domain: "VoiceInputManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "STT uploader not configured"])
        }

        let result = try await uploader.transcribe(audioURL: audioURL)
        logSuccess("Transcription successful", component: "Groq")
        logUserTranscript(result)

        return result
    }
}
