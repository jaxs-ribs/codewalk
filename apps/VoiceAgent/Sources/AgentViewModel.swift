import SwiftUI
import Combine
import AVFoundation

@MainActor
class AgentViewModel: ObservableObject {
    @Published var currentState: AgentState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var transcription: String = ""
    @Published var connectionStatus: String = "Disconnected"
    @Published var lastMessage: String = ""
    
    private var audioTimer: Timer?
    private var recorder: Recorder?
    private var sttUploader: STTUploader?
    private var ttsService: ElevenLabsTTS?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var relayWebSocket: RelayWebSocket?
    private var sessionId: String = ""
    private var token: String = ""
    private var pendingConfirmationId: String? = nil
    private var pendingPrompt: String? = nil
    
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
        
        // Initialize TTS service with ElevenLabs API
        if !env.elevenLabsKey.isEmpty {
            ttsService = ElevenLabsTTS(apiKey: env.elevenLabsKey)
            print("[VoiceAgent] ElevenLabs TTS service initialized")
        } else {
            print("[VoiceAgent] WARNING: No ElevenLabs API key found in .env")
        }
        
        sttUploader = STTUploader(groqApiKey: env.groqApiKey)
        print("[VoiceAgent] STTUploader initialized")
        
        // Initialize WebSocket relay connection
        setupWebSocket(env: env)
    }
    
    private func setupWebSocket(env: EnvConfig) {
        relayWebSocket = RelayWebSocket()
        
        // Setup WebSocket callbacks
        relayWebSocket?.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.connectionStatus = state.rawValue.capitalized
                print("[VoiceAgent] WebSocket state: \(state.rawValue)")
            }
        }
        
        relayWebSocket?.onAck = { [weak self] ack in
            Task { @MainActor in
                self?.lastMessage = "ACK: \(ack)"
                print("[VoiceAgent] Received ACK: \(ack)")
            }
        }
        
        // Handle Status messages (e.g., "cannot parse")
        relayWebSocket?.onStatus = { [weak self] level, text in
            Task { @MainActor in
                print("[VoiceAgent] Status (\(level)): \(text)")
                self?.lastMessage = "Status: \(text)"
                
                // Speak the status message
                if level == "info" {
                    let textLower = text.lowercased()
                    if textLower.contains("non-technical") || textLower.contains("non-coding") || 
                       textLower.contains("cannot") || textLower.contains("unclear") ||
                       textLower.contains("could not understand") {
                        // Non-command response
                        self?.speakResponse("This doesn't seem to be a command, I will ignore")
                    } else if textLower.contains("no active session") {
                        // No session running query response
                        self?.speakResponse("There's no active Claude Code session running right now")
                    } else if textLower.contains("active") && textLower.contains("session") && textLower.contains("running") {
                        // Active session status
                        self?.speakResponse("Claude Code is currently running a task")
                    } else if textLower.contains("starting claude code") {
                        // Executor launched successfully - speak the full message with the prompt
                        self?.speakResponse(text)
                    } else if textLower.contains("canceled") || textLower.contains("cancelled") {
                        // User canceled
                        self?.speakResponse("Cancelled")
                    } else {
                        // For any other info status (like summaries), speak it directly
                        print("[VoiceAgent] Speaking status: \(text)")
                        self?.speakResponse(text)
                    }
                }
            }
        }
        
        // Handle PromptConfirmation messages
        relayWebSocket?.onConfirmation = { [weak self] id, executor, prompt in
            Task { @MainActor in
                print("[VoiceAgent] Confirmation request - id: \(id ?? "nil"), executor: \(executor)")
                self?.lastMessage = "Confirm: \(prompt.prefix(50))..."
                
                // Store confirmation details and prompt for later
                self?.pendingConfirmationId = id
                self?.pendingPrompt = prompt
                
                // Ask for confirmation and return to idle
                self?.speakResponse("Do you want me to start a Claude Code session for this? Yes or no")
            }
        }
        
        // Use pre-configured session credentials from .env
        if !env.relayWsUrl.isEmpty && !env.sessionId.isEmpty && !env.token.isEmpty {
            sessionId = env.sessionId
            token = env.token
            print("[VoiceAgent] Using pre-configured session: \(sessionId)")
            print("[VoiceAgent] Connecting to relay: \(env.relayWsUrl)")
            relayWebSocket?.connect(url: env.relayWsUrl, sid: sessionId, tok: token)
        } else {
            print("[VoiceAgent] WARNING: Missing relay configuration")
            print("[VoiceAgent] - RELAY_WS_URL: \(env.relayWsUrl)")
            print("[VoiceAgent] - RELAY_SESSION_ID: \(env.sessionId)")
            print("[VoiceAgent] - RELAY_TOKEN: \(env.token.prefix(10))...")
        }
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
            // INTERRUPT TTS and go to idle
            interruptAndGoIdle()
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
                    
                    // Check if we have a pending confirmation (orchestrator is waiting)
                    if self.pendingConfirmationId != nil {
                        self.handleConfirmationResponse(transcript)
                    } else {
                        // Normal flow - send transcription to orchestrator
                        self.sendTranscriptionToOrchestrator(transcript)
                    }
                    
                    // Return to idle state
                    self.transitionTo(.idle)
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
    
    private func speakResponse(_ text: String) {
        print("[VoiceAgent] Speaking response: \(text)")
        
        guard let ttsService = ttsService else {
            print("[VoiceAgent] ERROR: TTS service not initialized")
            transitionTo(.idle)
            return
        }
        
        // Transition to talking state
        transitionTo(.talking)
        
        // Start simulated audio levels for visual feedback
        simulateAudioLevels()
        
        // Speak the text
        ttsService.speak(text: text) { [weak self] completed in
            Task { @MainActor in
                if completed {
                    print("[VoiceAgent] TTS completed normally")
                } else {
                    print("[VoiceAgent] TTS was interrupted")
                }
                
                // Only go to idle if we're still in talking state (not interrupted)
                if self?.currentState == .talking {
                    self?.transitionTo(.idle)
                }
            }
        }
    }
    
    private func interruptAndGoIdle() {
        print("[VoiceAgent] Interrupting TTS and going to idle")
        
        // Stop audio level simulation FIRST for instant visual feedback
        audioTimer?.invalidate()
        audioLevel = 0
        
        // Stop TTS immediately
        ttsService?.stop()
        
        // Transition to idle state instead of recording
        transitionTo(.idle)
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
        
        // Stop audio timer if not talking
        if newState != .talking {
            audioTimer?.invalidate()
            withAnimation(.easeOut(duration: 0.2)) {
                audioLevel = 0.0
            }
        }
        
        print("[VoiceAgent] State changed to: \(newState)")
    }
    
    private func sendTranscriptionToOrchestrator(_ text: String) {
        guard let relay = relayWebSocket else {
            print("[VoiceAgent] WARNING: WebSocket not connected, cannot send transcription")
            return
        }
        
        print("[VoiceAgent] Sending transcription to orchestrator: \(text)")
        relay.sendUserText(text)
        lastMessage = "Sent: \(text)"
    }
    
    private func handleConfirmationResponse(_ transcript: String) {
        print("[VoiceAgent] Parsing confirmation response: \(transcript)")
        
        // Parse yes/no using Groq LLM
        Task {
            let response = await parseYesNo(transcript)
            
            await MainActor.run {
                switch response {
                case .yes:
                    print("[VoiceAgent] User said YES")
                    self.sendConfirmationToOrchestrator(accept: true)
                    // Use the stored prompt in the message
                    if let prompt = self.pendingPrompt {
                        let truncatedPrompt = prompt.count > 50 ? 
                            String(prompt.prefix(47)) + "..." : prompt
                        self.speakResponse("Okay, starting Claude Code session with the instruction: \(truncatedPrompt)")
                    } else {
                        self.speakResponse("Okay, starting Claude Code session")
                    }
                case .no:
                    print("[VoiceAgent] User said NO")
                    self.sendConfirmationToOrchestrator(accept: false)
                    self.speakResponse("Rejected the starting of a session")
                case .unclear:
                    print("[VoiceAgent] Response unclear, asking again")
                    self.speakResponse("I didn't quite catch that. Could you please say yes or no?")
                    // Don't clear pending confirmation - still waiting
                    return
                }
                
                // Clear pending confirmation after handling yes/no
                self.pendingConfirmationId = nil
                self.pendingPrompt = nil
            }
        }
    }
    
    private func sendConfirmationToOrchestrator(accept: Bool) {
        guard let relay = relayWebSocket else {
            print("[VoiceAgent] WARNING: WebSocket not connected")
            return
        }
        
        print("[VoiceAgent] Sending confirmation response: \(accept ? "YES" : "NO")")
        relay.sendConfirmResponse(id: pendingConfirmationId, accept: accept)
        lastMessage = accept ? "Confirmed" : "Cancelled"
    }
    
    private enum YesNoResponse {
        case yes
        case no
        case unclear
    }
    
    private func parseYesNo(_ text: String) async -> YesNoResponse {
        // Simple heuristic for common cases
        let lower = text.lowercased()
        if lower.contains("yes") || lower.contains("yeah") || lower.contains("yep") || 
           lower.contains("sure") || lower.contains("ok") || lower.contains("okay") ||
           lower.contains("do it") || lower.contains("go ahead") || lower.contains("start") {
            return .yes
        }
        if lower.contains("no") || lower.contains("nope") || lower.contains("cancel") || 
           lower.contains("stop") || lower.contains("don't") || lower.contains("nevermind") {
            return .no
        }
        
        // Use Groq for ambiguous cases
        let env = EnvConfig.load()
        guard !env.groqApiKey.isEmpty else {
            print("[VoiceAgent] No Groq API key, using simple parsing")
            return .unclear
        }
        
        let prompt = """
        Classify this response as YES, NO, or UNCLEAR in response to the question "Do you want me to start a Claude Code session?"
        
        User said: "\(text)"
        
        Reply with only: YES, NO, or UNCLEAR
        """
        
        do {
            let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(env.groqApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "model": "llama-3.1-8b-instant",
                "messages": [
                    ["role": "system", "content": "You classify user responses as YES, NO, or UNCLEAR. Reply with only one word."],
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.1,
                "max_tokens": 10
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                let response = content.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                print("[VoiceAgent] Groq classified as: \(response)")
                
                switch response {
                case "YES": return .yes
                case "NO": return .no
                default: return .unclear
                }
            }
        } catch {
            print("[VoiceAgent] Error calling Groq: \(error)")
        }
        
        return .unclear
    }
    
    private func simulateAudioLevels() {
        audioTimer?.invalidate()
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