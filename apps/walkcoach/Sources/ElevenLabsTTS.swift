import Foundation
import AVFoundation

enum ElevenTTSError: Error {
    case badHTTPStatus(Int)
    case emptyAudio
    case invalidURL
}

/// Service for text-to-speech using ElevenLabs API
@MainActor
final class ElevenLabsTTS: NSObject {
    private let apiKey: String
    private let voiceId: String
    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    init(apiKey: String, voiceId: String = "flq6f7yk4E4fJM5XTYuZ") { // Michael voice
    // init(apiKey: String, voiceId: String = "GBv7mTt0atIp3Br8iCZE") { // Thomas voice
        self.apiKey = apiKey
        self.voiceId = voiceId
        super.init()
        log("Initialized with voice: \(voiceId)", category: .system, component: "ElevenLabsTTS")
    }

    /// Synthesizes text to speech and plays it with ULTRA LOW LATENCY
    /// - Parameter text: The text to convert to speech
    func synthesizeAndPlay(_ text: String) async throws {
        log("Synthesizing text to speech...", category: .tts, component: "ElevenLabsTTS")

        // Clean markdown from text
        let cleanedText = cleanMarkdown(text)

        // Synthesize to file
        let audioFileURL = try await synthesizeToFile(
            text: cleanedText,
            modelId: "eleven_flash_v2_5", // FASTEST model
            outputFormat: "mp3_22050_32"  // Small file for faster transfer
        )

        log("Audio synthesized successfully", category: .tts, component: "ElevenLabsTTS")

        // Play the audio
        try await playAudio(from: audioFileURL)
    }

    /// Stops any currently playing audio
    func stop() {
        log("Stopping playback", category: .tts, component: "ElevenLabsTTS")
        player?.stop()
        player = nil

        // Resume any pending continuation
        if let continuation = playbackContinuation {
            playbackContinuation = nil
            continuation.resume() // Resume without error for interruption
        }
    }

    var isSpeaking: Bool {
        return player?.isPlaying ?? false
    }

    /// Synthesizes text to an audio file
    private func synthesizeToFile(
        text: String,
        modelId: String,
        outputFormat: String
    ) async throws -> URL {
        let url = baseURL.appendingPathComponent("/v1/text-to-speech/\(voiceId)")
        log("Calling ElevenLabs API...", category: .network, component: "ElevenLabsTTS")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "output_format": outputFormat,
            "voice_settings": [
                "speed": 1.2,  // Increase speed by 20%
                "stability": 0.8,
                "similarity_boost": 0.8
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        log("Speech speed: 1.2x", category: .tts, component: "ElevenLabsTTS")

        let (data, response) = try await URLSession.shared.data(for: request)
        log("Received \(data.count) bytes of audio", category: .network, component: "ElevenLabsTTS")

        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid HTTP response", component: "ElevenLabsTTS")
            throw URLError(.badServerResponse)
        }

        log("HTTP Status: \(httpResponse.statusCode)", category: .network, component: "ElevenLabsTTS")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            logError("Bad HTTP status \(httpResponse.statusCode): \(errorBody)", component: "ElevenLabsTTS")
            throw ElevenTTSError.badHTTPStatus(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            logError("Empty audio data received", component: "ElevenLabsTTS")
            throw ElevenTTSError.emptyAudio
        }

        // Save to temporary file
        let ext = outputFormat.hasPrefix("mp3") ? "mp3" : "wav"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: fileURL)

        log("Audio saved (\(data.count) bytes)", category: .tts, component: "ElevenLabsTTS")

        return fileURL
    }

    /// Plays audio from a file URL
    private func playAudio(from url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation

            do {
                // Configure audio session for playback
                let audioSession = AVAudioSession.sharedInstance()

                // Use playAndRecord to keep mic ready but route to speaker for loud output
                try audioSession.setCategory(.playAndRecord,
                                            mode: .default,
                                            options: [.defaultToSpeaker, .allowBluetooth])

                // Force route to speaker for maximum volume
                try audioSession.overrideOutputAudioPort(.speaker)

                // Ensure session is active
                try audioSession.setActive(true, options: [])

                log("Audio session configured for playback", category: .tts, component: "ElevenLabsTTS")

                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                player?.volume = 1.0  // Maximum volume
                player?.delegate = self

                guard player?.play() == true else {
                    playbackContinuation = nil
                    continuation.resume(throwing: NSError(
                        domain: "ElevenLabsTTS",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to start playback"]
                    ))
                    return
                }

                log(String(format: "Playing audio (%.1f seconds)", player?.duration ?? 0), category: .tts, component: "ElevenLabsTTS")

                // Clean up the temporary file after a delay
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    try? FileManager.default.removeItem(at: url)
                    log("Audio playback completed", category: .tts, component: "ElevenLabsTTS")
                }

            } catch {
                playbackContinuation = nil
                continuation.resume(throwing: error)
            }
        }
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
extension ElevenLabsTTS: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            log("Playback finished: \(flag ? "success" : "interrupted")", category: .tts, component: "ElevenLabsTTS")

            // Resume continuation
            if let continuation = playbackContinuation {
                playbackContinuation = nil
                if flag {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ElevenLabsTTS",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Playback failed"]
                    ))
                }
            }

            self.player = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            logError("Audio decode error: \(error?.localizedDescription ?? "unknown")", component: "ElevenLabsTTS")

            if let continuation = playbackContinuation {
                playbackContinuation = nil
                continuation.resume(throwing: error ?? NSError(
                    domain: "ElevenLabsTTS",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Audio decode error"]
                ))
            }

            self.player = nil
        }
    }
}