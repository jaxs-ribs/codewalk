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
        print("[ElevenLabsTTS] Initialized with voice: \(voiceId)")
    }

    /// Synthesizes text to speech and plays it with ULTRA LOW LATENCY
    /// - Parameter text: The text to convert to speech
    func synthesizeAndPlay(_ text: String) async throws {
        print("[ElevenLabsTTS] Synthesizing: \(text.prefix(50))...")

        // Clean markdown from text
        let cleanedText = cleanMarkdown(text)

        // Synthesize to file
        let audioFileURL = try await synthesizeToFile(
            text: cleanedText,
            modelId: "eleven_flash_v2_5", // FASTEST model
            outputFormat: "mp3_22050_32"  // Small file for faster transfer
        )

        print("[ElevenLabsTTS] Audio file synthesized at: \(audioFileURL.path)")

        // Play the audio
        try await playAudio(from: audioFileURL)
    }

    /// Stops any currently playing audio
    func stop() {
        print("[ElevenLabsTTS] Stopping playback")
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
        print("[ElevenLabsTTS] Calling API at: \(url.absoluteString)")

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
        print("[ElevenLabsTTS] Request with speed 1.2x (20% faster)")

        let (data, response) = try await URLSession.shared.data(for: request)
        print("[ElevenLabsTTS] Received \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[ElevenLabsTTS] ERROR: Invalid HTTP response")
            throw URLError(.badServerResponse)
        }

        print("[ElevenLabsTTS] HTTP Status: \(httpResponse.statusCode)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("[ElevenLabsTTS] ERROR: Bad HTTP status \(httpResponse.statusCode), body: \(errorBody)")
            throw ElevenTTSError.badHTTPStatus(httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            print("[ElevenLabsTTS] ERROR: Empty audio data received")
            throw ElevenTTSError.emptyAudio
        }

        // Save to temporary file
        let ext = outputFormat.hasPrefix("mp3") ? "mp3" : "wav"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: fileURL)

        print("[ElevenLabsTTS] Audio saved to: \(fileURL.path), size: \(data.count) bytes")

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

                print("[ElevenLabsTTS] Audio session configured for loud playback")

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

                print("[ElevenLabsTTS] Playing audio, duration: \(player?.duration ?? 0) seconds")

                // Clean up the temporary file after a delay
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    try? FileManager.default.removeItem(at: url)
                    print("[ElevenLabsTTS] Cleaned up temp audio file")
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
            print("[ElevenLabsTTS] Finished playing audio successfully: \(flag)")

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
            print("[ElevenLabsTTS] Audio decode error: \(error?.localizedDescription ?? "unknown")")

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