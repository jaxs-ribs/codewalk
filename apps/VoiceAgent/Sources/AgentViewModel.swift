import SwiftUI
import Combine
import AVFoundation

@MainActor
class AgentViewModel: ObservableObject {
    @Published var currentState: AgentState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var transcription: String = ""
    
    private var audioTimer: Timer?
    private var recorder: Recorder?
    private var sttUploader: STTUploader?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    
    init() {
        print("[VoiceAgent] ViewModel initialized")
        setupServices()
    }
    
    private func setupServices() {
        // Initialize recorder immediately to pre-warm audio session
        recorder = Recorder()
        print("[VoiceAgent] Recorder initialized and pre-warming audio session")
        
        // Load environment config
        let env = EnvConfig.load()
        sttUploader = STTUploader(groqApiKey: env.groqApiKey)
        print("[VoiceAgent] STTUploader initialized")
    }
    
    func handleCircleTap() {
        print("[VoiceAgent] Circle tapped, current state: \(currentState)")
        
        switch currentState {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            // Can't interrupt transcription, wait for it to complete
            print("[VoiceAgent] Transcription in progress, please wait...")
        case .talking:
            // In future, will interrupt TTS here
            transitionTo(.recording)
        }
    }
    
    private func startRecording() {
        print("[VoiceAgent] Starting recording...")
        
        guard let recorder = recorder else {
            print("[VoiceAgent] ERROR: Recorder not initialized")
            return
        }
        
        // Start recording INSTANTLY (synchronous, but super fast)
        let started = recorder.startInstant()
        
        if started {
            // Only change state if recording actually started
            recordingStartTime = Date()
            transitionTo(.recording)
            
            // Start duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    if let startTime = self.recordingStartTime {
                        self.recordingDuration = Date().timeIntervalSince(startTime)
                    }
                }
            }
            
            print("[VoiceAgent] Recording started successfully")
        } else {
            print("[VoiceAgent] ERROR: Failed to start recording")
        }
    }
    
    private func stopRecordingAndTranscribe() {
        print("[VoiceAgent] Stopping recording...")
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        guard let recorder = recorder else {
            print("[VoiceAgent] ERROR: Recorder not initialized")
            return
        }
        
        guard let audioURL = recorder.stop() else {
            print("[VoiceAgent] ERROR: No audio file from recorder")
            transitionTo(.idle)
            return
        }
        
        print("[VoiceAgent] Recording saved to: \(audioURL.path)")
        print("[VoiceAgent] Recording duration: \(recordingDuration)s")
        
        // Only transcribe if recording was long enough (> 0.5 seconds)
        if recordingDuration < 0.5 {
            print("[VoiceAgent] Recording too short, skipping transcription")
            recordingDuration = 0
            transitionTo(.idle)
            return
        }
        
        transitionTo(.transcribing)
        transcribeAudio(from: audioURL)
    }
    
    private func transcribeAudio(from url: URL) {
        print("[VoiceAgent] Starting transcription...")
        
        guard let sttUploader = sttUploader else {
            print("[VoiceAgent] ERROR: STTUploader not initialized")
            transitionTo(.idle)
            return
        }
        
        Task {
            do {
                let transcript = try await sttUploader.transcribe(audioURL: url)
                
                await MainActor.run {
                    self.transcription = transcript
                    print("[VoiceAgent] =====================================")
                    print("[VoiceAgent] TRANSCRIPTION SUCCESS:")
                    print("[VoiceAgent] \(transcript)")
                    print("[VoiceAgent] =====================================")
                    
                    // Reset for next recording
                    self.recordingDuration = 0
                    transitionTo(.idle)
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
                
            } catch {
                print("[VoiceAgent] ERROR: Transcription failed: \(error)")
                await MainActor.run {
                    self.recordingDuration = 0
                    self.transitionTo(.idle)
                }
            }
        }
    }
    
    func transitionTo(_ newState: AgentState) {
        // Prepare haptic feedback first (pre-warm)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        
        // Ultra-fast animation for instant visual feedback
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8, blendDuration: 0)) {
            currentState = newState
        }
        
        // Fire haptic after state change
        if newState == .recording {
            generator.notificationOccurred(.success)
        } else if currentState == .recording {
            generator.notificationOccurred(.warning)
        }
        
        audioTimer?.invalidate()
        
        if newState == .talking {
            simulateAudioLevels()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                audioLevel = 0.0
            }
        }
        
        print("[VoiceAgent] State changed to: \(newState)")
    }
    
    private func simulateAudioLevels() {
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                let targetLevel = Float.random(in: 0.1...0.9)
                withAnimation(.easeInOut(duration: 0.1)) {
                    self.audioLevel = self.audioLevel * 0.7 + targetLevel * 0.3
                }
            }
        }
    }
}