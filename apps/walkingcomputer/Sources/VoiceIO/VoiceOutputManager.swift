import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Manages voice output: text-to-speech
@MainActor
class VoiceOutputManager {
    private let ttsManager: any TTSProtocol
    private let ttsProvider: TTSProvider

    #if canImport(UIKit)
    private let groqTTSManager: GroqTTSManager?
    private let elevenLabsTTS: ElevenLabsTTS?
    #endif

    init(config: EnvConfig, ttsManager: (any TTSProtocol)? = nil) {
        // Initialize TTS manager (iOS native or injected for testing)
        #if canImport(UIKit)
        self.ttsManager = ttsManager ?? TTSManager()
        #else
        if let provided = ttsManager {
            self.ttsManager = provided
        } else {
            fatalError("TTS manager must be provided when not running on iOS")
        }
        #endif

        // Determine TTS provider from launch arguments
        #if canImport(UIKit)
        if CommandLine.arguments.contains("--UseElevenLabs") {
            ttsProvider = .elevenLabs
            elevenLabsTTS = ElevenLabsTTS(apiKey: config.elevenLabsApiKey)
            groqTTSManager = nil
            log("Using ElevenLabs TTS", category: .tts, component: "VoiceOutputManager")
        } else if CommandLine.arguments.contains("--UseGroqTTS") {
            ttsProvider = .groq
            groqTTSManager = GroqTTSManager(groqApiKey: config.groqApiKey)
            elevenLabsTTS = nil
            log("Using Groq TTS with PlayAI voices", category: .tts, component: "VoiceOutputManager")
        } else {
            ttsProvider = .native
            groqTTSManager = nil
            elevenLabsTTS = nil
            log("Using iOS native TTS", category: .tts, component: "VoiceOutputManager")
        }
        #else
        // On macOS (tests), always use native (which is mocked)
        ttsProvider = .native
        log("Using mocked TTS for testing", category: .tts, component: "VoiceOutputManager")
        #endif
    }

    func speak(_ text: String) async {
        // Skip speaking context messages
        if ConversationContext.isContextMessage(text) {
            log("Skipping TTS for context message", category: .tts, component: "VoiceOutputManager")
            return
        }

        // Log the AI response
        logAIResponse(text)

        #if canImport(UIKit)
        switch ttsProvider {
        case .elevenLabs:
            if let elevenLabs = elevenLabsTTS {
                do {
                    try await elevenLabs.synthesizeAndPlay(text)
                } catch {
                    logError("ElevenLabs TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await ttsManager.speak(text, interruptible: true)
                }
            } else {
                await ttsManager.speak(text, interruptible: true)
            }
        case .groq:
            if let groqTTS = groqTTSManager {
                do {
                    try await groqTTS.synthesizeAndPlay(text)
                } catch {
                    logError("Groq TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await ttsManager.speak(text, interruptible: true)
                }
            } else {
                await ttsManager.speak(text, interruptible: true)
            }
        case .native:
            await ttsManager.speak(text, interruptible: true)
        }
        #else
        // macOS/testing: always use provided TTS manager
        await ttsManager.speak(text, interruptible: true)
        #endif
    }

    func stop() {
        #if canImport(UIKit)
        switch ttsProvider {
        case .elevenLabs:
            elevenLabsTTS?.stop()
        case .groq:
            groqTTSManager?.stop()
        case .native:
            ttsManager.stop()
        }
        #else
        ttsManager.stop()
        #endif
    }
}

// MARK: - TTS Provider

enum TTSProvider {
    case native
    case groq
    case elevenLabs
}
