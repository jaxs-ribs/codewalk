import Foundation
import AVFoundation

/// Simple TTS service using AVSpeechSynthesizer for placeholder
/// Will be replaced with ElevenLabs later
final class TTSService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: ((Bool) -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        
        // Ensure audio session is configured for playback
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use same session as recording (already active)
            try session.setCategory(.playAndRecord, 
                                   mode: .spokenAudio,
                                   options: [.defaultToSpeaker, .allowBluetooth])
            print("[TTS] Audio session configured for playback")
        } catch {
            print("[TTS] Failed to configure audio session: \(error)")
        }
    }
    
    func speak(text: String, completion: @escaping (Bool) -> Void) {
        print("[TTS] Speaking: \(text)")
        
        self.completion = completion
        
        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure voice and speed
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52  // Slightly faster than default
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Pre-utterance delay to avoid audio glitches
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        // Start speaking
        synthesizer.speak(utterance)
    }
    
    func stop() {
        print("[TTS] Stopping speech")
        synthesizer.stopSpeaking(at: .immediate)
        
        // Call completion with interrupted flag
        completion?(false)
        completion = nil
    }
    
    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("[TTS] Started speaking")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[TTS] Finished speaking")
        completion?(true)
        completion = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("[TTS] Speech cancelled")
        completion?(false)
        completion = nil
    }
}