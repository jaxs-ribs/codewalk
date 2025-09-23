import Foundation
import AVFoundation

// MARK: - Groq TTS Manager

@MainActor
class GroqTTSManager: NSObject {
    private let groqApiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/audio/speech"
    private let model = "playai-tts"
    private let voice: String
    private var audioPlayer: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    init(groqApiKey: String, voice: String = "Fritz-PlayAI") {
        self.groqApiKey = groqApiKey
        self.voice = voice
        super.init()
        print("[GroqTTSManager] Initialized with voice: \(voice)")
    }

    func synthesizeAndPlay(_ text: String) async throws {
        print("[GroqTTSManager] Synthesizing: \(text.prefix(50))...")

        // Clean markdown from text
        let cleanedText = cleanMarkdown(text)

        // Create request
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let requestBody: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": cleanedText,
            "response_format": "mp3"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("[GroqTTSManager] Sending request to Groq TTS...")

        // Perform request with retry logic
        let data = try await NetworkManager.shared.performRequestWithRetry(request)

        print("[GroqTTSManager] Received \(data.count) bytes of audio")

        // Play the audio
        try await playAudio(data)
    }

    private func playAudio(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation

            do {
                // Configure audio session
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
                try audioSession.setActive(true)

                // Create audio player
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()

                // Start playback
                guard audioPlayer?.play() == true else {
                    playbackContinuation = nil
                    continuation.resume(throwing: NSError(domain: "GroqTTSManager", code: -2,
                                                         userInfo: [NSLocalizedDescriptionKey: "Failed to start playback"]))
                    return
                }

                print("[GroqTTSManager] Started audio playback")
            } catch {
                playbackContinuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        audioPlayer?.stop()

        // Cancel any pending continuation
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume()  // Resume without error to allow interruption
        }

        audioPlayer = nil

        // Release audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[GroqTTSManager] Failed to release audio session: \(error)")
        }

        print("[GroqTTSManager] Stopped playback")
    }

    var isSpeaking: Bool {
        return audioPlayer?.isPlaying ?? false
    }

    private func cleanMarkdown(_ text: String) -> String {
        var cleaned = text

        // Remove markdown headers
        cleaned = cleaned.replacingOccurrences(of: #"#{1,6}\s+"#, with: "", options: .regularExpression)

        // Remove bold/italic markers
        cleaned = cleaned.replacingOccurrences(of: #"\*{1,3}([^\*]+)\*{1,3}"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"_{1,3}([^_]+)_{1,3}"#, with: "$1", options: .regularExpression)

        // Remove code blocks
        cleaned = cleaned.replacingOccurrences(of: #"```[^`]*```"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")

        // Remove links but keep text
        cleaned = cleaned.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)

        // Remove bullet points (multiline)
        let bulletPattern = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+"#, options: .anchorsMatchLines)
        cleaned = bulletPattern.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")

        // Remove numbered lists (multiline)
        let numberPattern = try! NSRegularExpression(pattern: #"^\s*\d+\.\s+"#, options: .anchorsMatchLines)
        cleaned = numberPattern.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")

        // Clean up extra whitespace
        cleaned = cleaned.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVAudioPlayerDelegate

extension GroqTTSManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Release audio session
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("[GroqTTSManager] Playback finished, released audio session")
            } catch {
                print("[GroqTTSManager] Failed to release audio session: \(error)")
            }

            // Resume continuation
            if let continuation = playbackContinuation {
                playbackContinuation = nil
                if flag {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "GroqTTSManager", code: -3,
                                                         userInfo: [NSLocalizedDescriptionKey: "Playback failed"]))
                }
            }

            audioPlayer = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            print("[GroqTTSManager] Decode error: \(error?.localizedDescription ?? "unknown")")

            if let continuation = playbackContinuation {
                playbackContinuation = nil
                continuation.resume(throwing: error ?? NSError(domain: "GroqTTSManager", code: -4,
                                                              userInfo: [NSLocalizedDescriptionKey: "Audio decode error"]))
            }

            audioPlayer = nil
        }
    }
}