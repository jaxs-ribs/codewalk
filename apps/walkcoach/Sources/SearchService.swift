import Foundation

// MARK: - Search Models

struct BraveSearchResponse: Codable {
    let web: BraveWebResults?
}

struct BraveWebResults: Codable {
    let results: [BraveResult]
}

struct BraveResult: Codable {
    let title: String
    let url: String
    let description: String?
}

struct FetchedPage {
    let url: String
    let content: String?
}

// MARK: - Search Service

class SearchService {
    private let braveApiKey: String
    private let groqApiKey: String
    private let braveSearchURL = "https://api.search.brave.com/res/v1/web/search"
    private let groqURL = "https://api.groq.com/openai/v1/chat/completions"

    // Configuration
    private let resultCount: Int
    private let fetchTimeoutSeconds: TimeInterval
    private let modelId: String
    private let maxConcurrentFetches = 4
    private let maxContentLength = 1500 // Characters per source

    init(config: EnvConfig) {
        self.braveApiKey = config.braveApiKey
        self.groqApiKey = config.groqApiKey
        self.resultCount = config.searchResultCount
        self.fetchTimeoutSeconds = TimeInterval(config.fetchTimeoutMs) / 1000.0
        self.modelId = config.searchModelId
        print("[SearchService] Initialized with model: \(modelId), \(resultCount) results, \(fetchTimeoutSeconds)s timeout")
    }

    // MARK: - Public Interface

    func search(query: String) async throws -> String {
        print("[SearchService] Starting search for: \(query)")
        let startTime = Date()

        // Step 1: Search Brave
        let searchResults = try await searchBrave(query: query)

        guard !searchResults.isEmpty else {
            return "No search results found. Try different keywords."
        }

        print("[SearchService] Found \(searchResults.count) search results")

        // Step 2: Fetch pages concurrently
        let urls = searchResults.map { $0.url }
        let fetchedPages = await fetchPagesConcurrently(urls: urls)

        let successfulFetches = fetchedPages.filter { $0.content != nil }.count
        print("[SearchService] Fetched \(successfulFetches)/\(fetchedPages.count) pages successfully")

        // Step 3: Build prompt
        let prompt = buildPrompt(query: query, results: searchResults, pages: fetchedPages)

        // Step 4: Get summary from Groq
        let summary = try await callGroq(prompt: prompt)

        let elapsed = Date().timeIntervalSince(startTime)
        log("Search completed in \(String(format: "%.2f", elapsed))s", category: .search, component: "SearchService")

        // Return clean TTS-friendly summary
        return cleanForTTS(summary)
    }

    // MARK: - Brave Search

    private func searchBrave(query: String) async throws -> [BraveResult] {
        var components = URLComponents(string: braveSearchURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(resultCount)),
            URLQueryItem(name: "country", value: "us"),
            URLQueryItem(name: "search_lang", value: "en")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(braveApiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw SearchError.rateLimitExceeded("Brave API rate limit reached. Please wait a moment.")
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.apiError(httpResponse.statusCode, "Brave API error")
        }

        let searchResponse = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
        return searchResponse.web?.results ?? []
    }

    // MARK: - Page Fetching

    private func fetchPagesConcurrently(urls: [String]) async -> [FetchedPage] {
        await withTaskGroup(of: FetchedPage.self) { group in
            // Limit concurrent fetches
            for (index, url) in urls.enumerated() {
                if index < maxConcurrentFetches {
                    group.addTask {
                        await self.fetchPage(url: url)
                    }
                }
            }

            var pages: [FetchedPage] = []
            for await page in group {
                pages.append(page)

                // Add next URL if available
                if pages.count < urls.count && pages.count < urls.count {
                    let nextIndex = maxConcurrentFetches + pages.count - 1
                    if nextIndex < urls.count {
                        group.addTask {
                            await self.fetchPage(url: urls[nextIndex])
                        }
                    }
                }
            }

            return pages
        }
    }

    private func fetchPage(url: String) async -> FetchedPage {
        print("[SearchService] Fetching: \(url)")

        guard let pageURL = URL(string: url) else {
            return FetchedPage(url: url, content: nil)
        }

        var request = URLRequest(url: pageURL, timeoutInterval: fetchTimeoutSeconds)
        request.setValue("Mozilla/5.0 (compatible; SearchService/1.0)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return FetchedPage(url: url, content: nil)
            }

            guard let html = String(data: data, encoding: .utf8) else {
                return FetchedPage(url: url, content: nil)
            }

            // Convert HTML to text
            let text = await extractTextFromHTML(html)

            print("[SearchService] Fetched \(text.count) chars from \(url)")

            return FetchedPage(url: url, content: text)

        } catch {
            print("[SearchService] Failed to fetch \(url): \(error.localizedDescription)")
            return FetchedPage(url: url, content: nil)
        }
    }

    // MARK: - HTML Processing

    private func extractTextFromHTML(_ html: String) async -> String {
        // Use smart extraction to get actual article content
        return extractArticleContent(from: html)
    }

    private func extractArticleContent(from html: String) -> String {
        // Step 1: Remove script, style, nav, footer, header tags and their content
        var cleanedHTML = html
        let tagsToRemove = [
            "script", "style", "nav", "footer", "header", "aside",
            "noscript", "iframe", "button", "form", "select"
        ]

        for tag in tagsToRemove {
            let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
            cleanedHTML = cleanedHTML.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Step 2: Extract content from article/main/content tags if they exist
        var articleContent = ""

        // Look for article, main, or content-like divs
        let contentPatterns = [
            "<article[^>]*>(.*?)</article>",
            "<main[^>]*>(.*?)</main>",
            "<div[^>]*class=\"[^\"]*content[^\"]*\"[^>]*>(.*?)</div>",
            "<div[^>]*class=\"[^\"]*article[^\"]*\"[^>]*>(.*?)</div>",
            "<div[^>]*class=\"[^\"]*post[^\"]*\"[^>]*>(.*?)</div>",
            "<div[^>]*class=\"[^\"]*entry[^\"]*\"[^>]*>(.*?)</div>",
            "<div[^>]*id=\"[^\"]*content[^\"]*\"[^>]*>(.*?)</div>"
        ]

        for pattern in contentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: cleanedHTML, range: NSRange(cleanedHTML.startIndex..., in: cleanedHTML)) {
                if let range = Range(match.range(at: 1), in: cleanedHTML) {
                    articleContent = String(cleanedHTML[range])
                    break
                }
            }
        }

        // If no article found, use the cleaned HTML
        let htmlToProcess = articleContent.isEmpty ? cleanedHTML : articleContent

        // Step 3: Extract text from paragraphs and headings
        var textBlocks: [String] = []

        // Extract paragraphs
        let paragraphPattern = "<p[^>]*>(.*?)</p>"
        if let regex = try? NSRegularExpression(pattern: paragraphPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let matches = regex.matches(in: htmlToProcess, range: NSRange(htmlToProcess.startIndex..., in: htmlToProcess))
            for match in matches {
                if let range = Range(match.range(at: 1), in: htmlToProcess) {
                    let text = String(htmlToProcess[range])
                    let cleaned = cleanText(text)
                    if cleaned.count > 20 {  // Skip very short paragraphs
                        textBlocks.append(cleaned)
                    }
                }
            }
        }

        // Extract headings for context
        let headingPattern = "<h[1-6][^>]*>(.*?)</h[1-6]>"
        if let regex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let matches = regex.matches(in: htmlToProcess, range: NSRange(htmlToProcess.startIndex..., in: htmlToProcess))
            for match in matches {
                if let range = Range(match.range(at: 1), in: htmlToProcess) {
                    let text = String(htmlToProcess[range])
                    let cleaned = cleanText(text)
                    if cleaned.count > 5 && cleaned.count < 200 {  // Reasonable heading length
                        textBlocks.append(cleaned)
                    }
                }
            }
        }

        // Step 4: If we still don't have much content, fall back to basic extraction
        if textBlocks.count < 3 {
            let basicText = stripHTML(from: htmlToProcess)
            return intelligentTruncate(basicText)
        }

        // Step 5: Join blocks and return
        let finalText = textBlocks.joined(separator: " ")
        return intelligentTruncate(finalText)
    }

    private func cleanText(_ text: String) -> String {
        // Remove HTML tags
        var cleaned = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        cleaned = cleaned
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")
            .replacingOccurrences(of: "&#[0-9]+;", with: " ", options: .regularExpression)

        // Clean whitespace
        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private func intelligentTruncate(_ text: String) -> String {
        // Look for actual content by finding sentences
        let sentences = text.components(separatedBy: ". ")
        var content: [String] = []
        var totalLength = 0

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip navigation-like text
            if trimmed.count > 30 &&
               !trimmed.lowercased().contains("cookie") &&
               !trimmed.lowercased().contains("privacy") &&
               !trimmed.lowercased().contains("terms of service") &&
               !trimmed.lowercased().contains("subscribe") &&
               !trimmed.lowercased().contains("sign up") &&
               !trimmed.lowercased().contains("log in") {
                content.append(trimmed)
                totalLength += trimmed.count
                if totalLength > 8000 {
                    break
                }
            }
        }

        if content.isEmpty {
            // Fallback to simple truncation
            return String(text.prefix(8000))
        }

        return content.joined(separator: ". ")
    }

    private func stripHTML(from html: String) -> String {
        // Fallback basic HTML stripping
        var text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        text = cleanText(text)

        return text
    }

    // MARK: - Prompt Building

    private func buildPrompt(query: String, results: [BraveResult], pages: [FetchedPage]) -> String {
        var prompt = "Query: \"\(query)\"\n\nSources (each: [index] title — url — snippet):\n"

        for (index, result) in results.enumerated() {
            let number = index + 1
            prompt.append("\n[\(number)] \(result.title) — \(result.url)\n")

            // Try to use fetched content, fall back to Brave snippet
            let snippet: String
            if let page = pages.first(where: { $0.url == result.url }),
               let content = page.content {
                snippet = String(content.prefix(maxContentLength))
            } else if let description = result.description {
                snippet = description
            } else {
                snippet = "No content available"
            }

            // Clean up snippet - be more aggressive about keeping content
            let cleaned = snippet
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count > 10 }  // Filter out very short lines
                .prefix(30)  // Get more lines
                .joined(separator: " ")

            prompt.append(cleaned)
            prompt.append("\n")
        }

        // Log the prompt for debugging
        print("[SearchService] Built prompt with \(results.count) results, total length: \(prompt.count) chars")
        if prompt.count > 0 {
            print("[SearchService] First 500 chars of prompt: \(String(prompt.prefix(500)))")
        }

        return prompt
    }

    // MARK: - Groq Summarization

    private func callGroq(prompt: String) async throws -> String {
        let systemPrompt = """
        You are a search result summarizer. Your ONLY job is to summarize what you find in the provided sources.

        CRITICAL RULES:
        - ONLY use information that appears in the sources provided
        - If the sources don't mention something, say "the search results don't mention that"
        - NEVER use your training data or prior knowledge
        - If sources conflict, say so
        - If no relevant information found, say "I didn't find information about that in the search results"

        Voice rules:
        - Write in complete, flowing sentences for text-to-speech
        - No citations, brackets, or markdown
        - Maximum 200 words for quick listening
        - Spell out abbreviations on first use
        """

        var request = URLRequest(url: URL(string: groqURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add explicit instruction to the prompt
        let finalPrompt = "Based ONLY on the following search results, provide a summary. Do NOT use any information outside of what's provided below:\n\n" + prompt

        let requestBody: [String: Any] = [
            "model": modelId,  // Use configured model
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": finalPrompt]
            ],
            "temperature": 0.1,  // Lower temperature for more faithful summarization
            "max_tokens": 400
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let data = try await NetworkManager.shared.performRequestWithRetry(request)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SearchError.invalidResponse
        }

        print("[SearchService] LLM Response (\(content.count) chars): \(content)")

        return content
    }

    // MARK: - TTS Cleanup

    private func cleanForTTS(_ text: String) -> String {
        // Remove any markdown or special characters that might have slipped through
        return text
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Search Errors

enum SearchError: LocalizedError {
    case invalidResponse
    case rateLimitExceeded(String)
    case apiError(Int, String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .rateLimitExceeded(let message):
            return message
        case .apiError(let code, let message):
            return "\(message): \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}