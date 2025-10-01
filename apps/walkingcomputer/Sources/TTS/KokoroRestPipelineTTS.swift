import Foundation
import AVFoundation

/// REST-based pipelined TTS for sentence-by-sentence playback
@MainActor
final class KokoroRestPipelineTTS: NSObject {
    private let apiKey: String
    private let voice: String
    private let baseURL = URL(string: "https://api.deepinfra.com/v1/inference/hexgrad/Kokoro-82M")!

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isPlaying = false
    private var pipelineTask: Task<Void, Never>?

    private var buffersCompleted = 0
    private var totalBuffers = 0

    private let crossFadeDuration: TimeInterval = 0.03 // 30ms cross-fade

    init(apiKey: String, voice: String = "af_bella") {
        self.apiKey = apiKey
        self.voice = voice
        super.init()
        log("Initialized pipeline TTS with voice: \(voice)", category: .system, component: "KokoroRestPipelineTTS")
    }

    /// Speak sentences with overlapped network + playback
    func speakSentences(_ sentences: [String]) async {
        guard !sentences.isEmpty else { return }

        // Stop any existing playback first
        stop()

        log("Starting pipelined playback for \(sentences.count) sentences", category: .tts, component: "KokoroRestPipelineTTS")

        // Reset counters
        buffersCompleted = 0
        totalBuffers = 0

        setupAudioEngine()

        pipelineTask = Task {
            var buffers: [AVAudioPCMBuffer] = []

            // Generate first sentence immediately
            if let firstBuffer = await synthesizeSentence(sentences[0]) {
                buffers.append(firstBuffer)
                totalBuffers += 1
                scheduleBuffer(firstBuffer)
                startPlaying()
            }

            // Pipeline remaining sentences
            for sentence in sentences.dropFirst() {
                guard !Task.isCancelled else { break }

                if let buffer = await synthesizeSentence(sentence) {
                    buffers.append(buffer)
                    totalBuffers += 1
                    scheduleBuffer(buffer)
                }
            }

            // Wait for playback to complete
            await waitForPlaybackComplete()
        }

        await pipelineTask?.value
    }

    func stop() {
        log("Stopping pipeline playback", category: .tts, component: "KokoroRestPipelineTTS")
        pipelineTask?.cancel()
        pipelineTask = nil

        playerNode?.stop()
        audioEngine?.stop()
        isPlaying = false
    }

    var isSpeaking: Bool {
        return isPlaying
    }

    // MARK: - Audio Setup

    private func setupAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                   mode: .default,
                                   options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(24000)
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            engine.attach(player)

            // Use Float32 format - required for AVAudioPlayerNode
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 24000,
                                      channels: 1,
                                      interleaved: false)!

            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.prepare()

            playerNode = player
            audioEngine = engine

            log("Audio engine configured for pipeline", category: .tts, component: "KokoroRestPipelineTTS")

        } catch {
            logError("Failed to setup audio: \(error)", component: "KokoroRestPipelineTTS")
        }
    }

    // MARK: - Synthesis

    private func synthesizeSentence(_ text: String) async -> AVAudioPCMBuffer? {
        let startTime = Date()
        log("Synthesizing: \(text.prefix(50))...", category: .network, component: "KokoroRestPipelineTTS")

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let body: [String: Any] = [
            "text": text,
            "voice": voice,
            "output_format": "wav",
            "sample_rate": 24000
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logError("Invalid HTTP response", component: "KokoroRestPipelineTTS")
                return nil
            }

            log("HTTP Status: \(httpResponse.statusCode)", category: .network, component: "KokoroRestPipelineTTS")

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                logError("HTTP error \(httpResponse.statusCode): \(errorBody.prefix(200))", component: "KokoroRestPipelineTTS")
                return nil
            }

            // Parse JSON response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logError("Failed to parse JSON", component: "KokoroRestPipelineTTS")
                return nil
            }

            // Extract and decode audio
            guard let audioData = extractAndDecodeAudio(from: json) else {
                logError("Failed to extract audio", component: "KokoroRestPipelineTTS")
                return nil
            }

            let elapsed = Date().timeIntervalSince(startTime) * 1000
            log(String(format: "Synthesized in %.0f ms (%d bytes)", elapsed, audioData.count),
               category: .tts, component: "KokoroRestPipelineTTS")

            // Convert to PCM buffer
            return createPCMBuffer(from: audioData)

        } catch {
            logError("Synthesis failed: \(error)", component: "KokoroRestPipelineTTS")
            return nil
        }
    }

    private func extractAndDecodeAudio(from json: [String: Any]) -> Data? {
        // Try direct audio field
        var audioField = json["audio"] as? String

        // Fallback: { "output": [ { "audio": "..." } ] }
        if audioField == nil, let output = json["output"] as? [[String: Any]],
           let first = output.first {
            audioField = first["audio"] as? String
        }

        guard var base64String = audioField else {
            logError("No audio field in response", component: "KokoroRestPipelineTTS")
            return nil
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
            logError("Failed to decode base64 audio", component: "KokoroRestPipelineTTS")
            return nil
        }

        return audioData
    }

    private func createPCMBuffer(from wavData: Data) -> AVAudioPCMBuffer? {
        // Parse WAV header (skip 44 bytes)
        guard wavData.count > 44 else {
            logError("WAV data too short", component: "KokoroRestPipelineTTS")
            return nil
        }

        let pcmData = wavData.dropFirst(44) // Skip WAV header

        // Create Float32 buffer for AVAudioPlayerNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                  sampleRate: 24000,
                                  channels: 1,
                                  interleaved: false)!

        let frameCount = UInt32(pcmData.count / 2) // 2 bytes per Int16 sample

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            logError("Failed to create PCM buffer", component: "KokoroRestPipelineTTS")
            return nil
        }

        buffer.frameLength = frameCount

        // Convert Int16 to Float32 [-1.0, 1.0]
        pcmData.withUnsafeBytes { bytes in
            let int16Samples = bytes.bindMemory(to: Int16.self)
            if let floatChannelData = buffer.floatChannelData {
                for i in 0..<Int(frameCount) {
                    floatChannelData[0][i] = Float(int16Samples[i]) / 32768.0
                }
            }
        }

        return buffer
    }

    // MARK: - Playback

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let player = playerNode else { return }

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.buffersCompleted += 1
                log("Buffer completed (\(self.buffersCompleted)/\(self.totalBuffers))", category: .tts, component: "KokoroRestPipelineTTS")
            }
        }
    }

    private func startPlaying() {
        guard !isPlaying, let engine = audioEngine, let player = playerNode else { return }

        do {
            try engine.start()
            player.play()
            isPlaying = true
            log("Playback started", category: .tts, component: "KokoroRestPipelineTTS")
        } catch {
            logError("Failed to start playback: \(error)", component: "KokoroRestPipelineTTS")
        }
    }

    private func waitForPlaybackComplete() async {
        // Wait until all buffers have completed
        while buffersCompleted < totalBuffers && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        log("Playback complete", category: .tts, component: "KokoroRestPipelineTTS")
    }
}
