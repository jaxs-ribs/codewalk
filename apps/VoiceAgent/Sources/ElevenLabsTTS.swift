import Foundation
import AVFoundation

enum ElevenTTSError: Error {
    case badHTTPStatus(Int)
    case emptyAudio
    case invalidURL
}

/// Service for text-to-speech using ElevenLabs API
final class ElevenLabsTTS: NSObject {
    private let apiKey: String
    private let voiceId = "GBv7mTt0atIp3Br8iCZE" // Thomas voice (same as VoiceRelaySwiftUI)
    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private var player: AVAudioPlayer?
    private var completion: ((Bool) -> Void)?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        print("[TTS] ElevenLabsTTS initialized with API key: \(String(apiKey.prefix(10)))...")
    }
    
    /// Synthesizes text to speech and plays it with ULTRA LOW LATENCY
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - completion: Callback when synthesis completes or fails (true = completed, false = interrupted)
    func speak(text: String, completion: @escaping (Bool) -> Void) {
        print("[TTS] speak called with text: '\(text)'")
        
        self.completion = completion
        
        Task {
            do {
                // Use Flash v2.5 for FASTEST response (75ms latency)
                let audioFileURL = try await synthesizeToFile(
                    text: text,
                    modelId: "eleven_flash_v2_5", // FASTEST model
                    outputFormat: "mp3_22050_32"  // Small file for faster transfer
                )
                
                print("[TTS] Audio file synthesized successfully at: \(audioFileURL.path)")
                
                DispatchQueue.main.async {
                    self.playAudio(from: audioFileURL)
                }
            } catch {
                print("[TTS] ERROR in speak: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    /// Stops any currently playing audio
    func stop() {
        print("[TTS] Stopping playback INSTANTLY")
        player?.stop()
        player = nil
        
        // DON'T reset audio session here - keep it ready for instant recording
        // The recorder will handle its own session configuration
        
        // Call completion with interrupted flag IMMEDIATELY
        completion?(false)
        completion = nil
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
        print("[TTS] Calling ElevenLabs API at: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "output_format": outputFormat,
            "voice_settings": [
                "speed": 1.2,  // Increase speed by 15% (range: 0.7 to 1.2)
                "stability": 0.8,
                "similarity_boost": 0.8
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("[TTS] Request with speed 1.15x (15% faster)")
        
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
    private func playAudio(from url: URL) {
        print("[TTS] playAudio called with URL: \(url.path)")
        
        do {
            // Quick audio session switch for playback
            let audioSession = AVAudioSession.sharedInstance()
            
            // Use playAndRecord to keep mic ready but route to speaker for loud output
            try audioSession.setCategory(.playAndRecord, 
                                        mode: .default, 
                                        options: [.defaultToSpeaker, .allowBluetooth])
            
            // Force route to speaker for maximum volume
            try audioSession.overrideOutputAudioPort(.speaker)
            
            // Session should already be active from Recorder initialization
            // Just ensure it's active
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true, options: [])
            }
            
            print("[TTS] Audio session configured for loud playback with recording standby")
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.volume = 1.0  // Set volume to maximum (1.0 = 100%)
            player?.enableRate = false  // Disable rate control for better quality
            player?.numberOfLoops = 0  // Play once
            
            // Set delegate to detect when playback finishes
            player?.delegate = self
            
            let isPlaying = player?.play() ?? false
            print("[TTS] Audio player started: \(isPlaying), volume: \(player?.volume ?? 0), duration: \(player?.duration ?? 0) seconds")
            
            // Clean up the temporary file after a delay
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 10) {
                try? FileManager.default.removeItem(at: url)
                print("[TTS] Cleaned up temp audio file")
            }
            
            if !isPlaying {
                completion?(false)
                completion = nil
            }
        } catch {
            print("[TTS] ERROR in playAudio: \(error.localizedDescription)")
            completion?(false)
            completion = nil
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension ElevenLabsTTS: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[TTS] Finished playing audio successfully: \(flag)")
        
        // DON'T reset audio session - keep it ready for next action
        // The recorder has its own pre-warmed session
        
        completion?(flag)
        completion = nil
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[TTS] Audio player decode error: \(error?.localizedDescription ?? "unknown")")
        completion?(false)
        completion = nil
    }
}