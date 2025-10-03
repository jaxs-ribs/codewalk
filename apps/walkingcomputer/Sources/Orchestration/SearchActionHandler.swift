import Foundation

/// Handles search-related actions
class SearchActionHandler: ActionHandler {
    private let perplexityService: PerplexitySearchService?
    private let braveService: SearchService?
    private let voiceOutput: VoiceOutputManager
    private let conversationContext: ConversationContext
    private let searchContext: SearchContext
    var lastResponse: String = "" {
        didSet {
            Task { @MainActor in
                statusCallback?(lastResponse)
            }
        }
    }
    private var statusCallback: (@MainActor (String) -> Void)?

    init(
        perplexityService: PerplexitySearchService?,
        braveService: SearchService?,
        voiceOutput: VoiceOutputManager,
        conversationContext: ConversationContext,
        searchContext: SearchContext
    ) {
        self.perplexityService = perplexityService
        self.braveService = braveService
        self.voiceOutput = voiceOutput
        self.conversationContext = conversationContext
        self.searchContext = searchContext
    }

    func setStatusCallback(_ callback: @escaping @MainActor (String) -> Void) {
        self.statusCallback = callback
    }

    func canHandle(_ action: ProposedAction) -> Bool {
        switch action {
        case .search, .deepSearch:
            return true
        default:
            return false
        }
    }

    func handle(_ action: ProposedAction) async {
        switch action {
        case .search(let query):
            await executeSearch(query: query, depth: .small)
        case .deepSearch(let query):
            await executeSearch(query: query, depth: .medium)
        default:
            break
        }
    }

    // MARK: - Search Execution

    private func executeSearch(query: String, depth: SearchDepth) async {
        // Prefer Perplexity if available
        if let perplexityService = perplexityService {
            await executePerplexitySearch(query: query, depth: depth)
        } else if let braveService = braveService {
            // Fallback to Brave search (always shallow)
            await executeBraveSearch(query: query)
        } else {
            lastResponse = "Search service not available. Check PERPLEXITY_API_KEY or BRAVE_API_KEY in .env"
            await speak(lastResponse)
        }
    }

    private func executePerplexitySearch(query: String, depth: SearchDepth) async {
        guard let perplexityService = perplexityService else { return }

        let depthDescription = depth == .medium ? "deep research" : "search"
        log("Executing Perplexity \(depthDescription) for: '\(query)'", category: .search, component: "SearchActionHandler")
        searchContext.updateQuery(query)

        let searchingMessage = depth == .medium
            ? "Doing deep research on \(query)..."
            : "Searching for \(query)..."
        lastResponse = searchingMessage
        await speak(searchingMessage)

        do {
            let summary = try await perplexityService.search(query: query, depth: depth)
            logSuccess("Perplexity \(depthDescription) successful, summary: \(summary.count) chars", component: "SearchActionHandler")

            // Strip think blocks before using for TTS
            let cleanedSummary = stripThinkBlocks(summary)
            lastResponse = cleanedSummary

            // Add search query to history
            let historyPrefix = depth == .medium ? "Deep research on: " : "Search for: "
            conversationContext.addUserMessage(historyPrefix + query)

            // Load raw search results into context (silently - no TTS)
            let contextType = depth == .medium ? "Deep research on '\(query)'" : "Search results for '\(query)'"
            conversationContext.addSilentContextMessage(summary, type: contextType)

            // Speak the cleaned search results (user hears this)
            await speak(cleanedSummary)
        } catch {
            logError("Perplexity \(depthDescription) failed: \(error)", component: "SearchActionHandler")
            lastResponse = "Sorry, the \(depthDescription) failed. Please try again."
            await speak(lastResponse)
        }
    }

    private func executeBraveSearch(query: String) async {
        guard let braveService = braveService else { return }

        log("Executing Brave search for: '\(query)'", category: .search, component: "SearchActionHandler")
        searchContext.updateQuery(query)
        lastResponse = "Searching for \(query)..."
        await speak("Searching for \(query)...")

        do {
            let summary = try await braveService.search(query: query)
            logSuccess("Brave search successful, summary: \(summary.count) chars", component: "SearchActionHandler")
            lastResponse = summary

            // Add search query to history
            conversationContext.addUserMessage("Search for: \(query)")

            // Load search results into context (silently - no TTS)
            conversationContext.addSilentContextMessage(summary, type: "Search results for '\(query)'")

            // Speak the search results (user hears this)
            await speak(summary)
        } catch {
            logError("Brave search failed: \(error)", component: "SearchActionHandler")
            lastResponse = "Search failed: \(error.localizedDescription)"

            await speak("The search didn't work. \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func stripThinkBlocks(_ content: String) -> String {
        // Remove <think>...</think> blocks from content
        let pattern = "<think>.*?</think>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: content.utf16.count)

        if let regex = regex {
            let cleaned = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return content
    }

    private func speak(_ text: String) async {
        await voiceOutput.speak(text)
    }
}
