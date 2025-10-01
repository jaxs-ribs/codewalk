import Foundation

/// Router that prefers streaming, falls back to pipeline
@MainActor
final class LowLatencyTTS {
    private let apiKey: String
    private let voice: String

    private let streamingTTS: KokoroStreamingTTS
    private let pipelineTTS: KokoroRestPipelineTTS

    private var streamingAvailable = true
    private var lastStreamingAttempt: Date?

    // Timeout for streaming probe - 4s to account for TTFA (~1.3s) + buffering + completion
    private let streamingTimeout: TimeInterval = 4.0

    init(apiKey: String, voice: String = "af_bella") {
        self.apiKey = apiKey
        self.voice = voice
        self.streamingTTS = KokoroStreamingTTS(apiKey: apiKey, voice: voice)
        self.pipelineTTS = KokoroRestPipelineTTS(apiKey: apiKey, voice: voice)

        log("Initialized low-latency TTS router", category: .system, component: "LowLatencyTTS")
    }

    /// Speak text with lowest possible latency
    func speak(_ text: String) async {
        log("Speaking: \(text.prefix(50))...", category: .tts, component: "LowLatencyTTS")

        // Try streaming first if available
        if shouldTryStreaming() {
            let streamingSuccess = await tryStreaming(text)

            if streamingSuccess {
                return
            } else {
                log("Streaming failed, falling back to pipeline", category: .tts, component: "LowLatencyTTS")
                streamingAvailable = false
            }
        }

        // Fall back to pipeline
        await usePipeline(text)
    }

    func stop() {
        streamingTTS.stop()
        pipelineTTS.stop()
    }

    var isSpeaking: Bool {
        return streamingTTS.isSpeaking || pipelineTTS.isSpeaking
    }

    // MARK: - Streaming

    private func shouldTryStreaming() -> Bool {
        // If disabled, check if enough time has passed to retry
        if !streamingAvailable {
            if let lastAttempt = lastStreamingAttempt,
               Date().timeIntervalSince(lastAttempt) < 60 { // Retry after 60s
                return false
            }
            // Reset for retry
            streamingAvailable = true
        }

        return true
    }

    private func tryStreaming(_ text: String) async -> Bool {
        lastStreamingAttempt = Date()

        // Split text into chunks (1-2 sentences at a time)
        let chunks = splitIntoChunks(text)

        // Create async stream
        let (stream, continuation) = AsyncStream<String>.makeStream()

        // Feed chunks to stream
        Task {
            for chunk in chunks {
                continuation.yield(chunk)
                try? await Task.sleep(nanoseconds: 100_000_000) // Small delay between chunks
            }
            continuation.finish()
        }

        // Start streaming - no timeout, let it complete naturally
        do {
            try await streamingTTS.speakStreaming(textChunks: stream)
            log("Streaming succeeded", category: .tts, component: "LowLatencyTTS")
            return true
        } catch {
            log("Streaming failed: \(error)", category: .tts, component: "LowLatencyTTS")
            return false
        }
    }

    private func splitIntoChunks(_ text: String) -> [String] {
        // Simple sentence splitter
        // For production, use NSLinguisticTagger for better results
        var chunks: [String] = []
        var currentChunk = ""

        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?;:\n"))

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Keep first chunk small for low TTFA
            if chunks.isEmpty && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = trimmed
                continue
            }

            // Add to current chunk
            if currentChunk.isEmpty {
                currentChunk = trimmed
            } else {
                currentChunk += ". " + trimmed
            }

            // Flush chunk if long enough (aim for 1-2 seconds of speech)
            if currentChunk.count > 80 {
                chunks.append(currentChunk)
                currentChunk = ""
            }
        }

        // Add remaining
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        // If no chunks, return original text
        if chunks.isEmpty {
            chunks.append(text)
        }

        log("Split into \(chunks.count) chunks", category: .tts, component: "LowLatencyTTS")
        return chunks
    }

    // MARK: - Pipeline Fallback

    private func usePipeline(_ text: String) async {
        log("Using pipeline fallback", category: .tts, component: "LowLatencyTTS")

        // Split into sentences
        let sentences = splitIntoSentences(text)
        await pipelineTTS.speakSentences(sentences)
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?;:\n"))
        return sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Timeout Helper

    private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    struct TimeoutError: Error {}
}
