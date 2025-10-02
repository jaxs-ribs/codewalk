import Foundation

/// Response from Groq STT API
struct STTResponse: Decodable {
    let text: String?
}

/// Uploads audio files to Groq API for Whisper transcription
final class STTUploader {
    private let apiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/audio/transcriptions"
    
    init(groqApiKey: String) {
        self.apiKey = groqApiKey
        log("Initialized with API key: \(apiKey.prefix(10))...", category: .system, component: "STT")
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        log("Starting transcription of: \(audioURL.lastPathComponent)", category: .stt)
        
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
        body.append("whisper-large-v3-turbo\r\n".data(using: .utf8)!)
        
        // Add response format field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // Add audio file
        // Detect file type from extension
        let isM4A = audioURL.pathExtension.lowercased() == "m4a"
        let filename = isM4A ? "audio.m4a" : "audio.wav"
        let contentType = isM4A ? "audio/mp4" : "audio/wav"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        
        let audioData = try Data(contentsOf: audioURL)
        body.append(audioData)
        
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        log("Uploading \(audioData.count) bytes to Groq...", category: .network, component: "STT")

        // Perform request with retry logic
        let data: Data
        do {
            data = try await NetworkManager.shared.performRequestWithRetry(request)
        } catch {
            logError("Network request failed after retries: \(error)", component: "STT")

            // Return a fallback message if offline
            if (error as NSError).domain == NSURLErrorDomain {
                return "[Network unavailable - please try again]"
            }
            throw error
        }
        
        // Parse response
        let sttResponse = try JSONDecoder().decode(STTResponse.self, from: data)
        
        guard let text = sttResponse.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "STTUploader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty transcription"])
        }
        
        logSuccess("Transcription completed", component: "STT")
        return text
    }
}