import Foundation

/// Service for summarizing Claude Code activity logs using Groq LLM
final class LogSummarizer {
    private let groqApiKey: String
    private let model: String = "llama-3.1-8b-instant"
    private let session: URLSession
    
    init(groqApiKey: String) {
        self.groqApiKey = groqApiKey
        self.session = URLSession(configuration: .default)
    }
    
    /// Summarizes activity logs from Claude Code session
    /// - Parameters:
    ///   - logs: Array of log entries (Date, level, message)
    ///   - completion: Callback with summarized text or error
    func summarizeLogs(_ logs: [(Date, String, String)], completion: @escaping (Result<String, Error>) -> Void) {
        guard !logs.isEmpty else {
            completion(.success("No activity to summarize"))
            return
        }
        
        // Format logs into readable text for the LLM
        let formattedLogs = logs.map { (date, level, message) in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeStr = formatter.string(from: date)
            return "\(timeStr) [\(level)] \(message)"
        }.joined(separator: "\n")
        
        // Prepare prompt for summarization
        let systemPrompt = """
        You are a concise log summarizer for Claude Code sessions.
        Extract and compress the MOST IMPORTANT information into bullet points.
        
        Focus on:
        - Tasks completed (with specific file names)
        - Errors resolved
        - Key changes made
        - Current status
        
        Be EXTREMELY concise - use fragments not sentences.
        Use bullet points starting with: •
        Skip filler words and obvious details.
        Prioritize actionable information over process descriptions.
        Maximum 2-3 words per bullet intro.
        Keep total response under 500 characters.
        """
        
        let userPrompt = """
        Please summarize these Claude Code activity logs:
        
        \(formattedLogs)
        """
        
        // Call Groq API
        callGroqAPI(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
    }
    
    private func callGroqAPI(systemPrompt: String, userPrompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            completion(.failure(NSError(domain: "LogSummarizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "LogSummarizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMsg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "LogSummarizer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorMsg)"])))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "LogSummarizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        completion(.success(content))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "LogSummarizer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        
        task.resume()
    }
}