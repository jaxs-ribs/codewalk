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
        print("[STTUploader] Initialized with API key: \(apiKey.prefix(10))...")
    }
    
    func transcribe(audioURL: URL) async throws -> String {
        print("[STTUploader] Starting transcription of: \(audioURL.lastPathComponent)")
        
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
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        let audioData = try Data(contentsOf: audioURL)
        body.append(audioData)
        
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("[STTUploader] Uploading \(audioData.count) bytes...")
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "STTUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[STTUploader] API Error (\(httpResponse.statusCode)): \(errorBody)")
            throw NSError(domain: "STTUploader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorBody])
        }
        
        // Parse response
        let sttResponse = try JSONDecoder().decode(STTResponse.self, from: data)
        
        guard let text = sttResponse.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "STTUploader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty transcription"])
        }
        
        print("[STTUploader] Transcription successful: \(text.prefix(50))...")
        return text
    }
}