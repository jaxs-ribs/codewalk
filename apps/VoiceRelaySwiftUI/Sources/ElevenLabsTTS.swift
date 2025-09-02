import Foundation
import AVFoundation

enum ElevenTTSError: Error {
    case badHTTPStatus(Int)
    case emptyAudio
    case invalidURL
}

/// Service for text-to-speech using ElevenLabs API
final class ElevenLabsTTS {
    private let apiKey: String
    private let voiceId = "GBv7mTt0atIp3Br8iCZE" // Thomas voice
    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private var player: AVAudioPlayer?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        print("[TTS] ElevenLabsTTS initialized with API key: \(String(apiKey.prefix(10)))...")
    }
    
    /// Synthesizes text to speech and plays it
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - modelId: The model to use (default: eleven_flash_v2_5 for fast generation)
    ///   - outputFormat: Audio format (default: mp3_22050_32 for small file size)
    ///   - completion: Callback when synthesis completes or fails
    func synthesizeAndPlay(
        text: String,
        modelId: String = "eleven_flash_v2_5",
        outputFormat: String = "mp3_22050_32",
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("[TTS] synthesizeAndPlay called with text: '\(text)'")
        print("[TTS] Model: \(modelId), Format: \(outputFormat)")
        
        Task {
            do {
                let audioFileURL = try await synthesizeToFile(
                    text: text,
                    modelId: modelId,
                    outputFormat: outputFormat
                )
                
                print("[TTS] Audio file synthesized successfully at: \(audioFileURL.path)")
                
                DispatchQueue.main.async {
                    self.playAudio(from: audioFileURL, completion: completion)
                }
            } catch {
                print("[TTS] ERROR in synthesizeAndPlay: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Synthesizes text to an audio file
    private func synthesizeToFile(
        text: String,
        modelId: String,
        outputFormat: String
    ) async throws -> URL {
        let url = baseURL.appendingPathComponent("/v1/text-to-speech/\(voiceId)")
        print("[TTS] Calling ElevenLabs API at: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "output_format": outputFormat
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("[TTS] Request body: \(body)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        print("[TTS] Received response with \(data.count) bytes")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[TTS] ERROR: Invalid HTTP response")
            throw URLError(.badServerResponse)
        }
        
        print("[TTS] HTTP Status Code: \(httpResponse.statusCode)")
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("[TTS] ERROR: Bad HTTP status \(httpResponse.statusCode), body: \(errorBody)")
            throw ElevenTTSError.badHTTPStatus(httpResponse.statusCode)
        }
        
        guard !data.isEmpty else {
            print("[TTS] ERROR: Empty audio data received")
            throw ElevenTTSError.emptyAudio
        }
        
        // Save to temporary file
        let ext = outputFormat.hasPrefix("mp3") ? "mp3" : "wav"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: fileURL)
        
        print("[TTS] Audio file saved to: \(fileURL.path)")
        print("[TTS] File size: \(data.count) bytes")
        
        return fileURL
    }
    
    /// Plays audio from a file URL
    private func playAudio(from url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[TTS] playAudio called with URL: \(url.path)")
        
        do {
            // Configure audio session for playback with maximum volume
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            
            // Set the audio session volume to maximum (if available on iOS 16+)
            if #available(iOS 16.0, *) {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            }
            
            print("[TTS] Audio session configured for playback")
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.volume = 1.0  // Set volume to maximum (1.0 = 100%)
            player?.enableRate = true
            player?.rate = 1.0  // Normal playback speed
            
            let isPlaying = player?.play() ?? false
            print("[TTS] Audio player started: \(isPlaying), volume: \(player?.volume ?? 0), duration: \(player?.duration ?? 0) seconds")
            
            // Clean up the temporary file after a delay
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10) {
                try? FileManager.default.removeItem(at: url)
                print("[TTS] Cleaned up temp audio file")
            }
            
            completion(.success(()))
        } catch {
            print("[TTS] ERROR in playAudio: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
    
    /// Stops any currently playing audio
    func stopPlayback() {
        player?.stop()
        player = nil
    }
}