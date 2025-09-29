import AVFoundation

// MARK: - TTS Manager

class TTSManager: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking: Bool = false
    private var speechContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        log("Initialized", category: .tts, component: "TTSManager")
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use playback category to work with recording
            try session.setCategory(.playAndRecord,
                                   mode: .voicePrompt,
                                   options: [.defaultToSpeaker,
                                           .allowBluetooth,
                                           .duckOthers])
            log("Audio session configured for TTS", category: .tts, component: "TTSManager")
        } catch {
            logError("Failed to configure audio session: \(error)", component: "TTSManager")
        }
    }

    // MARK: - Speech Methods

    func speak(_ text: String, interruptible: Bool = true) async {
        // Stop current speech if interruptible
        if interruptible && synthesizer.isSpeaking {
            stop()
            // Give synthesizer a moment to fully stop
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Clean the text for better TTS
        let cleanedText = cleanTextForTTS(text)

        // Debug: Log the full cleaned text length
        log("Full text length: \(cleanedText.count) chars", category: .tts, component: "TTSManager")
        log("First 200 chars: \(cleanedText.prefix(200))", category: .tts, component: "TTSManager")

        // Reconfigure and activate audio session every time
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                   mode: .voicePrompt,
                                   options: [.defaultToSpeaker,
                                           .allowBluetooth,
                                           .duckOthers])
            try session.setActive(true, options: [])
            log("Audio session reconfigured and activated", category: .tts, component: "TTSManager")
        } catch {
            logError("Failed to configure/activate audio session: \(error)", component: "TTSManager")
        }

        // Create utterance
        let utterance = AVSpeechUtterance(string: cleanedText)

        // Configure for walking pace (150-180 words per minute)
        utterance.rate = 0.52  // Faster pace for better flow
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9

        // Use enhanced voice if available
        if let voice = selectBestVoice() {
            utterance.voice = voice
        }

        // Pre and post delays for natural pacing
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        log("Speaking: \(cleanedText.prefix(50))...", category: .tts, component: "TTSManager")

        // Wait for speech to complete
        await withCheckedContinuation { continuation in
            speechContinuation = continuation
            synthesizer.speak(utterance)
            isSpeaking = true
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false

            // Resume continuation if speech was interrupted
            if let continuation = speechContinuation {
                speechContinuation = nil
                continuation.resume()
            }

            log("Speech stopped", category: .tts, component: "TTSManager")
        }
    }

    // MARK: - Helper Methods

    private func selectBestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()

        // Try to get enhanced voice first
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Look for enhanced quality voices
        if let enhancedVoice = voices.first(where: {
            $0.language == language &&
            $0.quality == .enhanced
        }) {
            log("Using enhanced voice: \(enhancedVoice.name)", category: .tts, component: "TTSManager")
            return enhancedVoice
        }

        // Fall back to default
        if let defaultVoice = AVSpeechSynthesisVoice(language: language) {
            log("Using default voice", category: .tts, component: "TTSManager")
            return defaultVoice
        }

        return nil
    }

    private func cleanTextForTTS(_ text: String) -> String {
        // Remove markdown headers and formatting for cleaner speech
        var cleaned = text

        // Remove markdown headers
        cleaned = cleaned.replacingOccurrences(of: "# ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "## ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "### ", with: "")

        // Remove asterisks (bold/italic)
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")

        // Remove backticks (code)
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")

        // Convert multiple newlines to periods for better pacing
        cleaned = cleaned.replacingOccurrences(of: "\n\n", with: ". ")
        cleaned = cleaned.replacingOccurrences(of: "\n", with: ". ")

        // Clean up multiple periods
        while cleaned.contains("..") {
            cleaned = cleaned.replacingOccurrences(of: "..", with: ".")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        log("Started speaking", category: .tts, component: "TTSManager")
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        log("Finished speaking", category: .tts, component: "TTSManager")
        isSpeaking = false

        // Resume continuation when speech finishes
        if let continuation = speechContinuation {
            speechContinuation = nil
            continuation.resume()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        log("Paused at: \(utterance.speechString.prefix(20))...", category: .tts, component: "TTSManager")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        log("Continued from pause", category: .tts, component: "TTSManager")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        log("Cancelled", category: .tts, component: "TTSManager")
        isSpeaking = false

        // Resume continuation when speech is cancelled
        if let continuation = speechContinuation {
            speechContinuation = nil
            continuation.resume()
        }
    }
}