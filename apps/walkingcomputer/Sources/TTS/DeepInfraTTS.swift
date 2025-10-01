import Foundation
import AVFoundation

enum DeepInfraTTSError: Error {
    case badHTTPStatus(Int)
    case emptyAudio
    case invalidURL
    case invalidBase64
}

/// Service for text-to-speech using DeepInfra Kokoro API
@MainActor
final class DeepInfraTTS: NSObject {
    private let apiKey: String
    private let voice: String
    private let baseURL = URL(string: "https://api.deepinfra.com/v1/inference/hexgrad/Kokoro-82M")!
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    init(apiKey: String, voice: String = "af_bella") {
        self.apiKey = apiKey
        self.voice = voice
        super.init()
        log("Initialized DeepInfra TTS with voice: \(voice)", category: .system, component: "DeepInfraTTS")
    }

    /// Synthesizes text to speech and plays it
    /// - Parameter text: The text to convert to speech
    func synthesizeAndPlay(_ text: String) async throws {
        log("Synthesizing text to speech...", category: .tts, component: "DeepInfraTTS")

        // Clean markdown from text
        let cleanedText = cleanMarkdown(text)

        // Pre-configure audio session while API call is in flight (optimization)
        Task { @MainActor in
            configureAudioSession()
        }

        // Synthesize to file with optimized settings
        let audioFileURL = try await synthesizeToFile(
            text: cleanedText,
            voice: voice,
            outputFormat: "wav"  // WAV: uncompressed but reliable
        )

        log("Audio synthesized successfully", category: .tts, component: "DeepInfraTTS")

        // Play the audio
        try await playAudio(from: audioFileURL)
    }

    /// Stops any currently playing audio
    func stop() {
        log("Stopping playback", category: .tts, component: "DeepInfraTTS")

        // Clear continuation BEFORE stopping player to prevent race condition
        // with delegate callback
        let continuation = playbackContinuation
        playbackContinuation = nil

        player?.stop()
        player = nil

        // Resume continuation after clearing it
        continuation?.resume()
    }

    var isSpeaking: Bool {
        return player?.isPlaying ?? false
    }

    /// Pre-configure audio session for low-latency playback
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true, options: [])
            log("Audio session pre-configured", category: .tts, component: "DeepInfraTTS")
        } catch {
            logError("Failed to pre-configure audio session: \(error)", component: "DeepInfraTTS")
        }
    }

    /// Synthesizes text to an audio file using DeepInfra Kokoro API
    private func synthesizeToFile(
        text: String,
        voice: String,
        outputFormat: String
    ) async throws -> URL {
        log("Calling DeepInfra Kokoro API...", category: .network, component: "DeepInfraTTS")

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0  // 10 second timeout

        let body: [String: Any] = [
            "text": text,
            "voice": voice,
            "output_format": outputFormat
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        log("Received response (\(data.count) bytes)", category: .network, component: "DeepInfraTTS")

        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid HTTP response", component: "DeepInfraTTS")
            throw URLError(.badServerResponse)
        }

        log("HTTP Status: \(httpResponse.statusCode)", category: .network, component: "DeepInfraTTS")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            logError("Bad HTTP status \(httpResponse.statusCode): \(errorBody)", component: "DeepInfraTTS")
            throw DeepInfraTTSError.badHTTPStatus(httpResponse.statusCode)
        }

        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logError("Failed to parse JSON response", component: "DeepInfraTTS")
            throw URLError(.cannotParseResponse)
        }

        // Extract base64 audio
        let audioBytes = try extractBase64Audio(from: json)

        guard !audioBytes.isEmpty else {
            logError("Empty audio data received", component: "DeepInfraTTS")
            throw DeepInfraTTSError.emptyAudio
        }

        // Save to temporary file
        let ext = outputFormat
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try audioBytes.write(to: fileURL)

        log("Audio saved (\(audioBytes.count) bytes)", category: .tts, component: "DeepInfraTTS")

        return fileURL
    }

    /// Extract base64-encoded audio from DeepInfra response
    private func extractBase64Audio(from json: [String: Any]) throws -> Data {
        // Try direct audio field first
        var audioField = json["audio"] as? String

        // Fallback: { "output": [ { "audio": "..." } ] }
        if audioField == nil, let output = json["output"] as? [[String: Any]],
           let first = output.first {
            audioField = first["audio"] as? String
        }

        guard var base64String = audioField else {
            logError("No audio field in response", component: "DeepInfraTTS")
            throw DeepInfraTTSError.invalidBase64
        }

        // Strip data URL prefix if present (e.g., "data:audio/wav;base64,")
        if base64String.contains(",") {
            base64String = base64String.components(separatedBy: ",")[1]
        }

        // Fix missing padding (base64 length must be % 4 == 0)
        let pad = base64String.count % 4
        if pad > 0 {
            base64String += String(repeating: "=", count: 4 - pad)
        }

        guard let audioData = Data(base64Encoded: base64String) else {
            logError("Failed to decode base64 audio", component: "DeepInfraTTS")
            throw DeepInfraTTSError.invalidBase64
        }

        return audioData
    }

    /// Plays audio from a file URL
    private func playAudio(from url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation

            do {
                // Audio session should already be pre-configured, but ensure it's active
                // This is much faster than full reconfiguration
                let audioSession = AVAudioSession.sharedInstance()
                if !audioSession.isOtherAudioPlaying {
                    try audioSession.setActive(true, options: [])
                }

                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                player?.volume = 1.0  // Maximum volume
                player?.delegate = self

                guard player?.play() == true else {
                    playbackContinuation = nil
                    continuation.resume(throwing: NSError(
                        domain: "DeepInfraTTS",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to start playback"]
                    ))
                    return
                }

                log(String(format: "Playing audio (%.1f seconds)", player?.duration ?? 0), category: .tts, component: "DeepInfraTTS")

                // Clean up the temporary file after a delay
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    try? FileManager.default.removeItem(at: url)
                    log("Temporary audio file cleaned up", category: .tts, component: "DeepInfraTTS")
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
extension DeepInfraTTS: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            log("Playback finished: \(flag ? "success" : "interrupted")", category: .tts, component: "DeepInfraTTS")

            // Resume continuation
            if let continuation = playbackContinuation {
                playbackContinuation = nil
                if flag {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "DeepInfraTTS",
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
            logError("Audio decode error: \(error?.localizedDescription ?? "unknown")", component: "DeepInfraTTS")

            if let continuation = playbackContinuation {
                playbackContinuation = nil
                continuation.resume(throwing: error ?? NSError(
                    domain: "DeepInfraTTS",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Audio decode error"]
                ))
            }

            self.player = nil
        }
    }
}
