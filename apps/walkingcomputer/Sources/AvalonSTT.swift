import Foundation

/// Response from Avalon STT API
struct AvalonSTTResponse: Decodable {
    let text: String
}

/// Uploads audio files to Avalon API for transcription
final class AvalonSTT {
    private let apiKey: String
    private let apiURL = "https://api.aquavoice.com/api/v1/audio/transcriptions"

    init(avalonApiKey: String) {
        self.apiKey = avalonApiKey
        log("Initialized with API key: \(apiKey.prefix(10))...", category: .system, component: "AvalonSTT")
    }

    func transcribe(audioURL: URL) async throws -> String {
        log("Starting transcription with Avalon: \(audioURL.lastPathComponent)", category: .stt, component: "AvalonSTT")

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build body
        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("avalon-v1-en\r\n".data(using: .utf8)!)

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)

        let audioData = try Data(contentsOf: audioURL)
        body.append(audioData)

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        log("Uploading \(audioData.count) bytes to Avalon...", category: .network, component: "AvalonSTT")

        // Perform request with retry logic
        let data: Data
        do {
            data = try await NetworkManager.shared.performRequestWithRetry(request)
        } catch {
            logError("Network request failed after retries: \(error)", component: "AvalonSTT")

            // Return a fallback message if offline
            if (error as NSError).domain == NSURLErrorDomain {
                return "[Network unavailable - please try again]"
            }
            throw error
        }

        // Parse response
        let sttResponse = try JSONDecoder().decode(AvalonSTTResponse.self, from: data)

        guard !sttResponse.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "AvalonSTT", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty transcription"])
        }

        logSuccess("Avalon transcription completed", component: "AvalonSTT")
        return sttResponse.text
    }
}