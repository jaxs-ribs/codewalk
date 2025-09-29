import Foundation

// MARK: - Search Evidence Models
// Note: BraveSearchResponse, BraveWebResults, and BraveResult are defined in SearchService.swift

struct SearchEvidence {
    let subquestion: String
    let snippets: [SearchSnippet]
}

struct SearchSnippet {
    let text: String
    let source: String
    let url: String
    let publishDate: String?
}

struct DomainStats {
    var count: Int = 0
    var urls: Set<String> = []
}

// MARK: - Deep Search Executor

class DeepSearchExecutor {
    private let braveApiKey: String
    private let braveSearchURL = "https://api.search.brave.com/res/v1/web/search"

    // Configuration
    private let maxConcurrentQueries = 4
    private let maxConcurrentFetches = 3
    private let maxSnippetsPerSubq = 8
    private let snippetLength = 150 // Target snippet length in words
    private let maxDomainsPerQuery = 2 // Limit per domain
    private let fetchTimeoutSeconds: TimeInterval = 5.0

    init(braveApiKey: String) {
        self.braveApiKey = braveApiKey
    }

    // MARK: - Main Execution

    func executeSearchPlan(_ plan: SearchPlan) async throws -> [SearchEvidence] {
        log("[EXECUTOR] Starting execution of \(plan.subqs.count) subquestions", category: .search)
        let startTime = Date()

        var allEvidence: [SearchEvidence] = []

        // Process each subquestion
        for (index, subq) in plan.subqs.enumerated() {
            log("[EXECUTOR] Processing subq \(index + 1)/\(plan.subqs.count): \(subq.q)", category: .search)

            // Execute all queries for this subquestion concurrently
            let evidence = await executeSubquestionQueries(subq)
            allEvidence.append(evidence)

            // Log progress
            log("[EXECUTOR] Subq \(index + 1) complete: \(evidence.snippets.count) snippets collected", category: .search)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let totalSnippets = allEvidence.reduce(0) { $0 + $1.snippets.count }
        log("[EXECUTOR] Execution complete in \(String(format: "%.2f", elapsed))s, total snippets: \(totalSnippets)", category: .search)

        // Log domain distribution
        logDomainDistribution(allEvidence)

        return allEvidence
    }

    // MARK: - Query Execution

    private func executeSubquestionQueries(_ subq: SearchSubQuestion) async -> SearchEvidence {
        let queries = subq.queries
        log("[EXECUTOR] Running \(queries.count) queries async for: \(subq.q)", category: .search)

        // Execute all queries concurrently
        let searchResults = await withTaskGroup(of: [BraveResult].self) { group in
            for query in queries {
                group.addTask {
                    await self.searchBrave(query: query, domains: subq.domains)
                }
            }

            var allResults: [BraveResult] = []
            for await results in group {
                allResults.append(contentsOf: results)
            }
            return allResults
        }

        log("[EXECUTOR] Query phase complete: \(searchResults.count) total results", category: .search)

        // Deduplicate by URL
        let uniqueUrls = Array(Set(searchResults.map { $0.url }))
        let dedupedResults = uniqueUrls.compactMap { url in
            searchResults.first(where: { $0.url == url })
        }

        // Apply domain limits
        let limitedResults = applyDomainLimits(dedupedResults, maxPerDomain: maxDomainsPerQuery)

        log("[EXECUTOR] After dedup and limits: \(limitedResults.count) URLs to fetch", category: .search)

        // Fetch page content
        let fetchedPages = await fetchPagesConcurrently(limitedResults)

        // Extract snippets
        let snippets = extractSnippets(from: fetchedPages, for: subq.q, maxSnippets: maxSnippetsPerSubq)

        return SearchEvidence(subquestion: subq.q, snippets: snippets)
    }

    // MARK: - Brave Search

    private func searchBrave(query: String, domains: [String]?) async -> [BraveResult] {
        log("[EXECUTOR] Query: \"\(query)\"", category: .search)

        var components = URLComponents(string: braveSearchURL)!

        // Add domain restrictions if specified
        var searchQuery = query
        if let domains = domains, !domains.isEmpty {
            let siteRestrictions = domains.map { "site:\($0)" }.joined(separator: " OR ")
            searchQuery = "\(query) (\(siteRestrictions))"
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "count", value: "5"), // Get top 5 per query
            URLQueryItem(name: "country", value: "us"),
            URLQueryItem(name: "search_lang", value: "en")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(braveApiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                log("[EXECUTOR] Search failed for query: \(query)", category: .search)
                return []
            }

            let searchResponse = try JSONDecoder().decode(BraveSearchResponse.self, from: data)
            let results = searchResponse.web?.results ?? []

            log("[EXECUTOR] Query \"\(query)\" → \(results.count) results", category: .search)
            return results

        } catch {
            logError("[EXECUTOR] Search error: \(error)", component: "DeepSearchExecutor")
            return []
        }
    }

    // MARK: - Page Fetching

    private func fetchPagesConcurrently(_ results: [BraveResult]) async -> [(result: BraveResult, content: String?)] {
        await withTaskGroup(of: (BraveResult, String?).self) { group in
            // Limit concurrent fetches
            for (index, result) in results.enumerated() {
                if index < maxConcurrentFetches {
                    group.addTask {
                        let content = await self.fetchPageContent(url: result.url)
                        return (result, content)
                    }
                }
            }

            var fetched: [(BraveResult, String?)] = []
            for await item in group {
                fetched.append(item)

                // Add next fetch if available
                if fetched.count < results.count {
                    let nextIndex = maxConcurrentFetches + fetched.count - 1
                    if nextIndex < results.count {
                        let result = results[nextIndex]
                        group.addTask {
                            let content = await self.fetchPageContent(url: result.url)
                            return (result, content)
                        }
                    }
                }
            }

            let successCount = fetched.filter { $0.1 != nil }.count
            log("[EXECUTOR] Fetched \(successCount)/\(fetched.count) pages successfully", category: .search)

            return fetched
        }
    }

    private func fetchPageContent(url: String) async -> String? {
        log("[EXECUTOR] Fetching: \(url)", category: .search)

        guard let pageURL = URL(string: url) else {
            return nil
        }

        var request = URLRequest(url: pageURL, timeoutInterval: fetchTimeoutSeconds)
        request.setValue("Mozilla/5.0 (compatible; DeepSearchExecutor/1.0)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Extract text content from HTML
            let text = extractTextFromHTML(html)
            log("[EXECUTOR] Fetched \(text.count) chars from \(url)", category: .search)

            return text

        } catch {
            log("[EXECUTOR] Failed to fetch \(url): \(error.localizedDescription)", category: .search)
            return nil
        }
    }

    // MARK: - Content Extraction

    private func extractTextFromHTML(_ html: String) -> String {
        // Remove script and style tags with their content (case insensitive, multi-line)
        var text = html
        text = text.replacingOccurrences(of: "(?s)<script[^>]*?>.*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "(?s)<style[^>]*?>.*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "(?s)<noscript[^>]*?>.*?</noscript>", with: " ", options: [.regularExpression, .caseInsensitive])

        // Remove comments
        text = text.replacingOccurrences(of: "<!--.*?-->", with: " ", options: .regularExpression)

        // Remove inline JavaScript events and attributes
        text = text.replacingOccurrences(of: "on\\w+=\"[^\"]*\"", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "on\\w+='[^']*'", with: "", options: .regularExpression)

        // Remove all HTML tags
        text = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any remaining JavaScript-looking content
        text = text.replacingOccurrences(of: "function\\s*\\([^)]*\\)\\s*\\{[^}]*\\}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\{[^}]*return[^}]*\\}", with: " ", options: .regularExpression)

        // Limit length
        if text.count > 8000 {
            text = String(text.prefix(8000))
        }

        return text
    }

    // MARK: - Snippet Extraction

    private func extractSnippets(from pages: [(result: BraveResult, content: String?)],
                                for question: String,
                                maxSnippets: Int) -> [SearchSnippet] {
        var snippets: [SearchSnippet] = []

        for (result, content) in pages {
            guard let text = content, !text.isEmpty else { continue }

            // Filter out garbage content first
            if !isValidContent(text) {
                log("[EXECUTOR] Skipping low-quality content from \(result.url)", category: .search)
                continue
            }

            // Split into sentences
            let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { isGoodSentence($0) }

            // Find relevant sentences
            let keywords = extractKeywords(from: question)
            var relevantChunks: [(text: String, score: Int)] = []

            // Create 2-3 sentence chunks
            for i in 0..<sentences.count {
                let chunk = sentences[i..<min(i+3, sentences.count)].joined(separator: ". ")
                if isGoodSnippet(chunk) {
                    let score = calculateRelevance(text: chunk, keywords: keywords)
                    if score > 0 {
                        relevantChunks.append((text: chunk + ".", score: score))
                    }
                }
            }

            // Sort by relevance and take top chunks
            relevantChunks.sort { $0.score > $1.score }
            let topChunks = relevantChunks.prefix(2) // Max 2 snippets per source

            for chunk in topChunks {
                snippets.append(SearchSnippet(
                    text: chunk.text,
                    source: extractDomain(from: result.url),
                    url: result.url,
                    publishDate: nil
                ))

                if snippets.count >= maxSnippets {
                    break
                }
            }

            if snippets.count >= maxSnippets {
                break
            }
        }

        log("[EXECUTOR] Extracted \(snippets.count) snippets for: \(question)", category: .search)

        // Log first snippet as example
        if let firstSnippet = snippets.first {
            let preview = String(firstSnippet.text.prefix(100))
            log("[EXECUTOR] First snippet: \"\(preview)...\" from \(firstSnippet.source)", category: .search)
        }

        return snippets
    }

    // MARK: - Content Quality Functions

    private func isValidContent(_ text: String) -> Bool {
        // Check if content has enough substance
        let words = text.split(separator: " ")
        if words.count < 50 { return false }  // Too short to be useful

        // Check for UI/navigation garbage
        let garbagePatterns = ["Cookie", "Subscribe", "Sign up", "Log in", "Privacy Policy",
                              "Terms of Service", "Accept cookies", "Newsletter"]
        let garbageCount = garbagePatterns.filter { text.contains($0) }.count
        if garbageCount > 3 { return false }  // Too much UI noise

        return true
    }

    private func isGoodSentence(_ sentence: String) -> Bool {
        // Filter out short fragments
        if sentence.count < 30 { return false }

        // Filter out UI elements
        let badPatterns = ["Login", "Loading", "Menu", "Click here", "Read more",
                          "Subscribe", "Follow us", "Share this", "Comments"]
        for pattern in badPatterns {
            if sentence.contains(pattern) { return false }
        }

        // Must have actual words
        let words = sentence.split(separator: " ")
        if words.count < 5 { return false }

        return true
    }

    private func isGoodSnippet(_ text: String) -> Bool {
        // Require substantive content
        let words = text.split(separator: " ")
        guard words.count >= 20 && words.count <= 150 else { return false }  // Good length range

        // Filter out code/JavaScript
        if text.contains("function") && text.contains("return") { return false }
        if text.contains("getElementById") { return false }
        if text.contains("var ") || text.contains("const ") { return false }

        // Filter out excessive special characters (likely code or garbage)
        let specialChars = CharacterSet(charactersIn: "{}[]()<>;")
        let specialCount = text.unicodeScalars.filter { specialChars.contains($0) }.count
        if specialCount > 5 { return false }

        return true
    }

    // MARK: - Utility Functions

    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction - split and filter common words
        let commonWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
                              "of", "with", "by", "from", "about", "what", "how", "why", "when",
                              "where", "which", "who", "are", "is", "was", "were", "been", "be"])

        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !commonWords.contains($0) }
    }

    private func calculateRelevance(text: String, keywords: [String]) -> Int {
        let lowerText = text.lowercased()
        var score = 0

        for keyword in keywords {
            if lowerText.contains(keyword) {
                score += 1
            }
        }

        return score
    }

    private func extractDomain(from url: String) -> String {
        guard let urlComponents = URLComponents(string: url),
              let host = urlComponents.host else {
            return url
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func applyDomainLimits(_ results: [BraveResult], maxPerDomain: Int) -> [BraveResult] {
        var domainCounts: [String: Int] = [:]
        var limited: [BraveResult] = []

        for result in results {
            let domain = extractDomain(from: result.url)
            let count = domainCounts[domain] ?? 0

            if count < maxPerDomain {
                limited.append(result)
                domainCounts[domain] = count + 1
            }
        }

        return limited
    }

    private func logDomainDistribution(_ evidence: [SearchEvidence]) {
        var domainStats: [String: DomainStats] = [:]

        for item in evidence {
            for snippet in item.snippets {
                let domain = snippet.source
                if domainStats[domain] == nil {
                    domainStats[domain] = DomainStats()
                }
                domainStats[domain]!.count += 1
                domainStats[domain]!.urls.insert(snippet.url)
            }
        }

        // Calculate max domain share
        let totalSnippets = evidence.reduce(0) { $0 + $1.snippets.count }
        if totalSnippets > 0 {
            let maxDomainCount = domainStats.values.map { $0.count }.max() ?? 0
            let maxDomainShare = Double(maxDomainCount) / Double(totalSnippets)

            log("[EXECUTOR] Domain distribution: \(domainStats.count) unique domains", category: .search)
            log("[EXECUTOR] Max domain share: \(String(format: "%.1f%%", maxDomainShare * 100))", category: .search)

            // Log top domains
            let topDomains = domainStats.sorted { $0.value.count > $1.value.count }.prefix(3)
            for (domain, stats) in topDomains {
                log("[EXECUTOR]   \(domain): \(stats.count) snippets from \(stats.urls.count) URLs", category: .search)
            }
        }
    }
}