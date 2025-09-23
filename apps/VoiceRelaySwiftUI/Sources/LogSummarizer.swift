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
    
    /// Summarizes pre-filtered text from Claude Code session
    /// - Parameters:
    ///   - filteredText: Pre-filtered and formatted log text
    ///   - completion: Callback with summarized text or error
    func summarizeFilteredText(_ filteredText: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("[TTS] summarizeFilteredText called with text length: \(filteredText.count)")
        guard !filteredText.isEmpty else {
            print("[TTS] Filtered text is empty, returning placeholder")
            completion(.success("No activity to summarize"))
            return
        }
        
        // Prepare prompt for summarization of pre-filtered content
        let systemPrompt = """
        You are a formal meeting narrator summarizing a Claude Code session.
        Write in PAST TENSE as if reporting what was accomplished.
        Be professional but concise.
        
        Format:
        • Use bullet points starting with: •
        • Write in past tense (searched, created, fixed, implemented)
        • Be factual and formal like a status report
        • Maximum 3-4 words per bullet intro
        • Keep total response under 350 characters
        • Group related actions together
        
        Example style:
        • Searched for existing files
        • Created snake game components
        • Fixed compilation errors
        • Implemented game logic
        """
        
        let userPrompt = """
        Summarize what was accomplished in this Claude Code session:
        
        \(filteredText)
        """
        
        // Call Groq API
        print("[TTS] Calling Groq API for summarization")
        callGroqAPI(systemPrompt: systemPrompt, userPrompt: userPrompt, completion: completion)
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
        You are a formal meeting narrator summarizing a Claude Code session.
        Write in PAST TENSE as if reporting what was accomplished.
        
        Focus on:
        - Tasks completed (with specific file names)
        - Errors resolved
        - Key changes made
        - Final status
        
        Format:
        • Use bullet points starting with: •
        • Write in past tense (searched, created, fixed, implemented)
        • Be factual and formal like a status report
        • Maximum 3-4 words per bullet intro
        • Keep total response under 500 characters
        """
        
        let userPrompt = """
        Please summarize these Claude Code activity logs:
        
        \(formattedLogs)
        """
        
        // Call Groq API
        print("[TTS] Calling Groq API for summarization")
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