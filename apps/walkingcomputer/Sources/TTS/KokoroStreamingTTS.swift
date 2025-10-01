import Foundation
import AVFoundation

enum StreamingError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
}

/// Lock-free ring buffer for PCM audio streaming
class PCMRingBuffer {
    private var buffer: [Int16]
    private let capacity: Int
    private var writeIndex = 0
    private var readIndex = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Int16](repeating: 0, count: capacity)
    }

    func write(_ samples: [Int16]) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            buffer[writeIndex % capacity] = sample
            writeIndex += 1
        }
    }

    func read(count: Int) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }

        let available = writeIndex - readIndex
        let toRead = min(count, available)
        var samples = [Int16](repeating: 0, count: count)

        for i in 0..<toRead {
            samples[i] = buffer[readIndex % capacity]
            readIndex += 1
        }

        // Fill rest with zeros if underrun
        return samples
    }

    func availableForRead() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return writeIndex - readIndex
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        readIndex = 0
    }
}

/// Streaming TTS client using DeepInfra's ElevenLabs-compatible endpoint
@MainActor
final class KokoroStreamingTTS: NSObject {
    private let apiKey: String
    private let voice: String
    private let baseURL = "https://api.deepinfra.com"

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var pcmBuffer: PCMRingBuffer?
    private var isPlaying = false
    private var streamingTask: Task<Void, Error>?
    private var streamingComplete = false

    // Latency tracking
    private var ttfaTimestamp: Date?
    private var firstSoundTimestamp: Date?

    // Buffer size: 1 second at 24kHz = 24000 samples, 4x for safety
    private let bufferSize = 24000 * 4
    private let targetBufferMs = 800  // Wait for 800ms before starting to avoid underruns

    init(apiKey: String, voice: String = "af_bella") {
        self.apiKey = apiKey
        self.voice = voice
        super.init()
        log("Initialized streaming TTS with voice: \(voice)", category: .system, component: "KokoroStreamingTTS")
    }

    /// Speak streaming text chunks as they arrive
    func speakStreaming(textChunks: AsyncStream<String>) async throws {
        // Stop any existing playback first
        stop()

        log("Starting streaming playback", category: .tts, component: "KokoroStreamingTTS")

        // Reset state
        ttfaTimestamp = nil
        firstSoundTimestamp = nil
        streamingComplete = false

        // Setup audio
        setupAudioEngine()
        pcmBuffer?.reset()

        // Start streaming task
        streamingTask = Task {
            for await chunk in textChunks {
                guard !Task.isCancelled else { break }
                try await streamChunk(chunk)
            }
            // Mark streaming as complete
            await MainActor.run {
                self.streamingComplete = true
                log("Streaming complete, buffer will drain naturally", category: .tts, component: "KokoroStreamingTTS")
            }
        }

        try await streamingTask?.value

        // Wait for buffer to drain (no timeout here - streaming already succeeded)
        log("Waiting for buffer to drain...", category: .tts, component: "KokoroStreamingTTS")
        while isPlaying && (pcmBuffer?.availableForRead() ?? 0) > 100 {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Stop playback
        stop()
        log("Playback complete, engine stopped", category: .tts, component: "KokoroStreamingTTS")
    }

    /// Stop playback and cleanup
    func stop() {
        log("Stopping streaming playback", category: .tts, component: "KokoroStreamingTTS")
        streamingTask?.cancel()
        streamingTask = nil

        audioEngine?.stop()
        isPlaying = false
    }

    var isSpeaking: Bool {
        return isPlaying
    }

    // MARK: - Audio Setup

    private func setupAudioEngine() {
        do {
            // Configure audio session with reasonable buffer size
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                   mode: .default,
                                   options: [.duckOthers])
            try session.setPreferredSampleRate(24000)
            try session.setPreferredIOBufferDuration(0.02) // 20ms buffer - more stable
            try session.setActive(true)

            log("Audio session configured: 24kHz, playback mode", category: .tts, component: "KokoroStreamingTTS")

            // Setup engine
            let engine = AVAudioEngine()
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                      sampleRate: 24000,
                                      channels: 1,
                                      interleaved: true)!

            // Initialize ring buffer
            pcmBuffer = PCMRingBuffer(capacity: bufferSize)

            // Create source node
            let buffer = pcmBuffer!
            var callbackCount = 0
            var zeroSampleCount = 0
            var lastLogTime = Date()

            let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self = self else { return noErr }

                callbackCount += 1
                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let available = buffer.availableForRead()
                let samples = buffer.read(count: Int(frameCount))

                // Count zero samples
                let zeros = samples.filter { $0 == 0 }.count
                if zeros > 0 {
                    zeroSampleCount += 1
                }

                // Log audio callback activity every 500ms
                let now = Date()
                if now.timeIntervalSince(lastLogTime) > 0.5 {
                    Task { @MainActor in
                        let bufferMs = (available * 1000) / 24000
                        log("📊 Callback #\(callbackCount): buffer=\(bufferMs)ms, zeros=\(zeros)/\(frameCount), playing=\(self.isPlaying), complete=\(self.streamingComplete)",
                           category: .tts, component: "KokoroStreamingTTS")
                    }
                    lastLogTime = now
                }

                // Warn on buffer underrun (only if streaming isn't complete)
                if available < Int(frameCount) && self.isPlaying && !self.streamingComplete {
                    Task { @MainActor in
                        log("⚠️ Buffer underrun: needed \(frameCount), had \(available)",
                           category: .tts, component: "KokoroStreamingTTS")
                    }
                }

                for frame in 0..<Int(frameCount) {
                    for buffer in ablPointer {
                        let buf = UnsafeMutableBufferPointer<Int16>(buffer)
                        buf[frame] = samples[frame]
                    }
                }

                // Log first sound
                if self.firstSoundTimestamp == nil && samples.contains(where: { $0 != 0 }) {
                    Task { @MainActor in
                        self.firstSoundTimestamp = Date()
                        if let ttfa = self.ttfaTimestamp, let firstSound = self.firstSoundTimestamp {
                            let latency = firstSound.timeIntervalSince(ttfa) * 1000
                            log(String(format: "First sound: %.0f ms after TTFA", latency),
                               category: .tts, component: "KokoroStreamingTTS")
                        }
                    }
                }

                return noErr
            }

            sourceNode = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()

            audioEngine = engine

            log("Audio engine configured", category: .tts, component: "KokoroStreamingTTS")

        } catch {
            logError("Failed to setup audio: \(error)", component: "KokoroStreamingTTS")
        }
    }

    // MARK: - Streaming

    private func streamChunk(_ text: String) async throws {
        let startTime = Date()
        log("Streaming chunk: \(text.prefix(50))...", category: .network, component: "KokoroStreamingTTS")

        // Build request - use standard inference endpoint
        let urlString = "\(baseURL)/v1/inference/hexgrad/Kokoro-82M"
        guard let url = URL(string: urlString) else {
            logError("Invalid streaming URL", component: "KokoroStreamingTTS")
            throw StreamingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        // Use same params as deepinfra.py
        let body: [String: Any] = [
            "text": text,
            "voice": voice,
            "output_format": "pcm",
            "sample_rate": 24000
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Stream response
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid HTTP response", component: "KokoroStreamingTTS")
            throw StreamingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Try to read error body
            var errorBody = ""
            for try await byte in asyncBytes.prefix(1000) {
                errorBody.append(Character(UnicodeScalar(byte)))
            }
            logError("HTTP error \(httpResponse.statusCode): \(errorBody)", component: "KokoroStreamingTTS")
            throw StreamingError.httpError(httpResponse.statusCode, errorBody)
        }

        log("Streaming started, receiving chunks...", category: .network, component: "KokoroStreamingTTS")

        var byteCount = 0
        var pcmData = Data()

        for try await byte in asyncBytes {
            guard !Task.isCancelled else { break }

            pcmData.append(byte)
            byteCount += 1

            // TTFA: log first byte
            if ttfaTimestamp == nil {
                ttfaTimestamp = Date()
                let ttfa = ttfaTimestamp!.timeIntervalSince(startTime) * 1000
                log(String(format: "TTFA: %.0f ms", ttfa), category: .tts, component: "KokoroStreamingTTS")
            }

            // Process in chunks of ~100ms (2400 samples = 4800 bytes)
            if pcmData.count >= 4800 {
                processPCMData(pcmData)
                pcmData.removeAll(keepingCapacity: true)
            }
        }

        // Process remaining data
        if !pcmData.isEmpty {
            processPCMData(pcmData)
        }

        let totalMs = (byteCount / 2 * 1000) / 24000
        log("Streaming chunk complete: \(byteCount) bytes (\(totalMs)ms audio)", category: .network, component: "KokoroStreamingTTS")
    }

    private func processPCMData(_ data: Data) {
        // Convert bytes to Int16 samples (little-endian)
        let samples = data.withUnsafeBytes { bytes -> [Int16] in
            let buffer = bytes.bindMemory(to: Int16.self)
            return Array(buffer)
        }

        pcmBuffer?.write(samples)

        // Start playing once we have enough buffer
        if !isPlaying {
            let available = pcmBuffer?.availableForRead() ?? 0
            let targetSamples = 24000 * targetBufferMs / 1000

            if available >= targetSamples {
                startPlaying()
            }
        }
    }

    private func startPlaying() {
        guard !isPlaying, let engine = audioEngine else { return }

        do {
            let bufferLevel = pcmBuffer?.availableForRead() ?? 0
            let bufferMs = (bufferLevel * 1000) / 24000
            log("▶️ Starting audio engine (buffer: \(bufferMs)ms, \(bufferLevel) samples)", category: .tts, component: "KokoroStreamingTTS")

            try engine.start()
            isPlaying = true
            log("Playback started", category: .tts, component: "KokoroStreamingTTS")
        } catch {
            logError("Failed to start engine: \(error)", component: "KokoroStreamingTTS")
        }
    }
}
