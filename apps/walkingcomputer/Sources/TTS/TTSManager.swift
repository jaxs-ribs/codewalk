import AVFoundation

// MARK: - TTS Manager

class TTSManager: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        print("[TTSManager] Initialized")
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
            print("[TTSManager] Audio session configured for TTS")
        } catch {
            print("[TTSManager] Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Speech Methods

    func speak(_ text: String, interruptible: Bool = true) {
        // Stop current speech if interruptible
        if interruptible && synthesizer.isSpeaking {
            stop()
        }

        // Clean the text for better TTS
        let cleanedText = cleanTextForTTS(text)

        // Create utterance
        let utterance = AVSpeechUtterance(string: cleanedText)

        // Configure for walking pace (150-180 words per minute)
        utterance.rate = 0.52  // Slightly faster than default (0.5)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9

        // Use enhanced voice if available
        if let voice = selectBestVoice() {
            utterance.voice = voice
        }

        // Pre and post delays for natural pacing
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        // Start speaking
        synthesizer.speak(utterance)
        isSpeaking = true

        print("[TTSManager] Speaking: \(cleanedText.prefix(50))...")
    }

    func speakChunked(_ text: String, chunks: [String]) {
        // For chunked reading (used in Phase 7 phasing)
        // This will be expanded later for phase-by-phase reading
        speak(chunks.first ?? text)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            print("[TTSManager] Speech stopped")
        }
    }

    func pause() {
        if synthesizer.isSpeaking && !synthesizer.isPaused {
            synthesizer.pauseSpeaking(at: .word)
            print("[TTSManager] Speech paused")
        }
    }

    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            print("[TTSManager] Speech resumed")
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
            print("[TTSManager] Using enhanced voice: \(enhancedVoice.name)")
            return enhancedVoice
        }

        // Fall back to default
        if let defaultVoice = AVSpeechSynthesisVoice(language: language) {
            print("[TTSManager] Using default voice")
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
        print("[TTSManager] Started speaking")
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[TTSManager] Finished speaking")
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("[TTSManager] Paused at: \(utterance.speechString.prefix(20))...")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("[TTSManager] Continued from pause")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("[TTSManager] Cancelled")
        isSpeaking = false
    }
}