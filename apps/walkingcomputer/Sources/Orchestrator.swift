import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AudioToolbox)
import AudioToolbox
#endif

// MARK: - Orchestrator State

enum OrchestratorState {
    case idle
    case conversing
    case executing
}

// MARK: - TTS Provider

enum TTSProvider {
    case native
    case groq
    case elevenLabs
    case deepInfra
    case lowLatency  // Streaming + pipeline fallback
}

// MARK: - Action Queue Item

struct ActionQueueItem {
    let action: ProposedAction
    let id = UUID()
}

// MARK: - Orchestrator

@MainActor
class Orchestrator: ObservableObject {
    @Published var state: OrchestratorState = .idle
    @Published var isExecuting: Bool = false  // IoGuard equivalent
    @Published var lastResponse: String = ""
    @Published var conversationHistory: [(role: String, content: String)] = []

    private var actionQueue: [ActionQueueItem] = []
    private let artifactManager: ArtifactManager
    private let assistantClient: AssistantClient
    private let ttsManager: any TTSProtocol
    private let router: Router

    #if canImport(UIKit)
    private let groqTTSManager: GroqTTSManager?
    private let elevenLabsTTS: ElevenLabsTTS?
    private let deepInfraTTS: DeepInfraTTS?
    private let lowLatencyTTS: LowLatencyTTS?
    #endif

    private let ttsProvider: TTSProvider
    private var searchService: SearchService?  // Legacy Brave search
    private var perplexityService: PerplexitySearchService?  // New Perplexity search
    private var lastSearchQuery: String?

    init(config: EnvConfig, ttsManager: (any TTSProtocol)? = nil) {
        // Initialize artifact manager
        artifactManager = ArtifactManager()

        // Initialize assistant client
        assistantClient = AssistantClient(groqApiKey: config.groqApiKey, modelName: config.llmModelId)

        // Initialize router
        router = Router(groqApiKey: config.groqApiKey, modelId: config.llmModelId)

        // Initialize TTS manager (iOS native or injected for testing)
        #if canImport(UIKit)
        self.ttsManager = ttsManager ?? TTSManager()
        #else
        if let provided = ttsManager {
            self.ttsManager = provided
        } else {
            fatalError("TTS manager must be provided when not running on iOS")
        }
        #endif

        // Determine TTS provider from launch arguments
        #if canImport(UIKit)
        if CommandLine.arguments.contains("--UseElevenLabs") {
            ttsProvider = .elevenLabs
            elevenLabsTTS = ElevenLabsTTS(apiKey: config.elevenLabsApiKey)
            groqTTSManager = nil
            deepInfraTTS = nil
            lowLatencyTTS = nil
            log("Using ElevenLabs TTS", category: .tts, component: "Orchestrator")
        } else if CommandLine.arguments.contains("--UseGroqTTS") {
            ttsProvider = .groq
            groqTTSManager = GroqTTSManager(groqApiKey: config.groqApiKey)
            elevenLabsTTS = nil
            deepInfraTTS = nil
            lowLatencyTTS = nil
            log("Using Groq TTS with PlayAI voices", category: .tts, component: "Orchestrator")
        } else if CommandLine.arguments.contains("--UseNativeTTS") {
            ttsProvider = .native
            groqTTSManager = nil
            elevenLabsTTS = nil
            deepInfraTTS = nil
            lowLatencyTTS = nil
            log("Using iOS native TTS", category: .tts, component: "Orchestrator")
        } else if CommandLine.arguments.contains("--UseDeepInfraREST") {
            // Old DeepInfra REST-only (for comparison)
            ttsProvider = .deepInfra
            deepInfraTTS = DeepInfraTTS(apiKey: config.deepInfraApiKey)
            groqTTSManager = nil
            elevenLabsTTS = nil
            lowLatencyTTS = nil
            log("Using DeepInfra Kokoro TTS (REST only)", category: .tts, component: "Orchestrator")
        } else {
            // Default: Low-latency streaming + pipeline fallback
            ttsProvider = .lowLatency
            lowLatencyTTS = LowLatencyTTS(apiKey: config.deepInfraApiKey)
            groqTTSManager = nil
            elevenLabsTTS = nil
            deepInfraTTS = nil
            log("Using Low-Latency Kokoro TTS (streaming + fallback, default)", category: .tts, component: "Orchestrator")
        }
        #else
        // On macOS (tests), always use native (which is mocked)
        ttsProvider = .native
        log("Using mocked TTS for testing", category: .tts, component: "Orchestrator")
        #endif

        log("Initialized with ArtifactManager, AssistantClient, and TTS", category: .system, component: "Orchestrator")

        // Initialize PerplexitySearchService if API key is available
        if !config.perplexityApiKey.isEmpty {
            perplexityService = PerplexitySearchService(apiKey: config.perplexityApiKey)
            log("PerplexitySearchService initialized", category: .system, component: "Orchestrator")
        } else if !config.braveApiKey.isEmpty {
            // Fallback to Brave search if no Perplexity key
            searchService = SearchService(config: config)
            log("SearchService (Brave) initialized as fallback", category: .system, component: "Orchestrator")
        }
    }

    // MARK: - Queue Management

    func enqueueAction(_ action: ProposedAction) {
        log("Enqueueing action: \(action)", category: .orchestrator)

        let item = ActionQueueItem(action: action)
        actionQueue.append(item)

        // Process queue if not already executing
        if !isExecuting {
            Task {
                await processQueue()
            }
        }
    }

    // MARK: - Test Mode Support

    /// Inject a text prompt directly, bypassing STT. For testing only.
    func injectPrompt(_ text: String) async {
        log("Test mode: injecting prompt: \(text)", category: .orchestrator)

        // Add to conversation history as user input
        addUserTranscript(text)

        // Route the prompt through the router (like production)
        do {
            let recentMessages = conversationHistory.suffix(10).map { "\($0.role): \($0.content)" }
            let context = RouterContext(recentMessages: Array(recentMessages), lastSearchQuery: lastSearchQuery)
            let response = try await router.route(transcript: text, context: context)

            // Enqueue the routed action
            enqueueAction(response.action)

            // Wait for completion
            await waitForCompletion()
        } catch {
            logError("Test mode: Router failed: \(error)", component: "Orchestrator")
            lastResponse = "Routing failed: \(error.localizedDescription)"
        }
    }

    /// Wait for orchestrator to finish all queued actions
    func waitForCompletion() async {
        while isExecuting || !actionQueue.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }

    private func processQueue() async {
        guard !actionQueue.isEmpty, !isExecuting else { return }

        log("Processing queue with \(actionQueue.count) items", category: .orchestrator)

        // Set executing flag (IoGuard)
        isExecuting = true
        state = .executing

        while !actionQueue.isEmpty {
            let item = actionQueue.removeFirst()
            await executeAction(item.action)
        }

        // Clear executing flag
        isExecuting = false
        state = .idle
    }

    // MARK: - Action Execution

    private func executeAction(_ action: ProposedAction) async {
        log("Executing action: \(action)", category: .orchestrator)

        switch action {
        case .writeDescription:
            await writeDescription()
        case .writePhasing:
            await writePhasing()
        case .writeBoth:
            await writeDescriptionAndPhasing()
        case .readDescription:
            await readDescription()
        case .readPhasing:
            await readPhasing()
        case .readSpecificPhase(let phaseNumber):
            await readSpecificPhase(phaseNumber)
        case .editDescription(let content):
            await editDescription(content: content)
        case .editPhasing(let phaseNumber, let content):
            await editPhasing(phaseNumber: phaseNumber, content: content)
        case .conversation(let content):
            await handleConversation(content)
        case .repeatLast:
            // Already displayed in lastResponse
            break
        case .stop:
            lastResponse = "Stopped"
        case .copyDescription:
            await copyDescriptionAction()
        case .copyPhasing:
            await copyPhasingAction()
        case .copyBoth:
            await copyBothAction()
        case .search(let query):
            await executeSearch(query: query, depth: .small)
        case .deepSearch(let query):
            await executeSearch(query: query, depth: .medium)
        }
    }

    // MARK: - Search Execution

    private func executeSearch(query: String, depth: SearchDepth) async {
        // Prefer Perplexity if available
        if let perplexityService = perplexityService {
            await executePerplexitySearch(query: query, depth: depth)
        } else if let searchService = searchService {
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
        log("Executing Perplexity \(depthDescription) for: '\(query)'", category: .search, component: "Orchestrator")
        lastSearchQuery = query

        let searchingMessage = depth == .medium
            ? "Doing deep research on \(query)..."
            : "Searching for \(query)..."
        lastResponse = searchingMessage
        await speak(searchingMessage)

        do {
            let summary = try await perplexityService.search(query: query, depth: depth)
            logSuccess("Perplexity \(depthDescription) successful, summary: \(summary.count) chars", component: "Orchestrator")

            // Strip think blocks before using for TTS
            let cleanedSummary = stripThinkBlocks(summary)
            lastResponse = cleanedSummary

            // Add search result to conversation history (keep full response for context)
            let historyPrefix = depth == .medium ? "Deep research on: " : "Search for: "
            addUserTranscript(historyPrefix + query)
            addAssistantResponse(summary)  // Keep full response in history

            // Speak the cleaned search results
            await speak(cleanedSummary)
        } catch {
            logError("Perplexity \(depthDescription) failed: \(error)", component: "Orchestrator")
            lastResponse = "Sorry, the \(depthDescription) failed. Please try again."
            await speak(lastResponse)
        }
    }

    private func executeBraveSearch(query: String) async {
        guard let searchService = searchService else { return }

        log("Executing Brave search for: '\(query)'", category: .search, component: "Orchestrator")
        lastSearchQuery = query
        lastResponse = "Searching for \(query)..."
        await speak("Searching for \(query)...")

        do {
            let summary = try await searchService.search(query: query)
            logSuccess("Brave search successful, summary: \(summary.count) chars", component: "Orchestrator")
            lastResponse = summary

            // Add search result to conversation history
            addUserTranscript("Search for: \(query)")
            addAssistantResponse(summary)

            // Speak the search results
            await speak(summary)
        } catch {
            logError("Brave search failed: \(error)", component: "Orchestrator")
            lastResponse = "Search failed: \(error.localizedDescription)"

            await speak("The search didn't work. \(error.localizedDescription)")
        }
    }

    private func copyDescriptionAction() async {
        if copyDescriptionToClipboard() {
            await speak(lastResponse)
        } else {
            await speak(lastResponse)
        }
    }

    private func copyPhasingAction() async {
        if copyPhasingToClipboard() {
            await speak(lastResponse)
        } else {
            await speak(lastResponse)
        }
    }

    private func copyBothAction() async {
        if copyBothToClipboard() {
            await speak(lastResponse)
        } else {
            await speak(lastResponse)
        }
    }

    // MARK: - Artifact Operations (Placeholder for Phase 5)

    private func writeDescription() async {
        _ = await writeArtifact(.description)
    }

    private func writePhasing() async {
        _ = await writeArtifact(.phasing)
    }

    private func writeDescriptionAndPhasing() async {
        await speak("Writing description...")
        let descriptionSuccess = await writeArtifact(.description, shouldSpeak: false)
        await speak(descriptionSuccess ? "Description written." : "Failed to write description")

        await speak("Writing phasing...")
        let phasingSuccess = await writeArtifact(.phasing, shouldSpeak: false)
        await speak(phasingSuccess ? "Phasing written." : "Failed to write phasing")

        switch (descriptionSuccess, phasingSuccess) {
        case (true, true):
            lastResponse = "Description and phasing written."
        case (true, false):
            lastResponse = "Description written, but writing phasing failed."
        case (false, true):
            lastResponse = "Phasing written, but writing description failed."
        case (false, false):
            lastResponse = "Failed to write description and phasing."
        }

        if !descriptionSuccess || !phasingSuccess {
            await speak(lastResponse)
        }
    }

    @discardableResult
    private func writeArtifact(_ type: ArtifactType, shouldSpeak: Bool = true) async -> Bool {
        lastResponse = "Writing \(type.displayName)..."
        if shouldSpeak {
            await speak(lastResponse)
        }

        do {
            let content = try await generateContent(for: type, shouldSpeak: shouldSpeak)

            if artifactManager.safeWrite(filename: type.filename, content: content) {
                lastResponse = "\(type.displayName.capitalized) written."
                addAssistantWriteConfirmation(for: type)

                if shouldSpeak {
                    await speak(lastResponse)
                }
                return true
            } else {
                lastResponse = "Failed to write \(type.displayName)"
                if shouldSpeak {
                    await speak(lastResponse)
                }
                return false
            }
        } catch {
            lastResponse = handleGenerationError(error, for: type.displayName)
            if shouldSpeak {
                await speak(lastResponse)
            }
            return false
        }
    }

    private func generateContent(for type: ArtifactType, shouldSpeak: Bool) async throws -> String {
        switch type {
        case .description:
            return try await assistantClient.generateDescription(
                conversationHistory: conversationHistory
            )
        case .phasing:
            // For phasing, use multi-pass generation with status updates
            var statusCallbackToUse: ((String) -> Void)? = nil
            if shouldSpeak {
                statusCallbackToUse = { [weak self] status in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.lastResponse = status
                        await self.speak(status)
                    }
                }
            }

            return try await assistantClient.generatePhasing(
                conversationHistory: conversationHistory,
                statusCallback: statusCallbackToUse
            )
        }
    }

    private func addAssistantWriteConfirmation(for type: ArtifactType) {
        switch type {
        case .description:
            addAssistantResponse("I've written the project description based on our conversation.")
        case .phasing:
            addAssistantResponse("I've written the project phasing based on our conversation.")
        }
    }

    private func readDescription() async {
        if let content = artifactManager.safeRead(filename: "description.md") {
            lastResponse = "Reading description..."
            log("Read description (\(content.count) chars)", category: .artifacts, component: "Orchestrator")

            // Speak the content using TTS
            await speak(content)
        } else {
            lastResponse = "No description yet."

            // Speak the error message
            await speak(self.lastResponse)

            // List what files exist
            let files = artifactManager.listArtifacts()
            log("Current artifacts: \(files.joined(separator: ", "))", category: .artifacts, component: "Orchestrator")
        }
    }

    private func readPhasing() async {
        if let content = artifactManager.safeRead(filename: "phasing.md") {
            lastResponse = "Reading phasing..."
            log("Read phasing (\(content.count) chars)", category: .artifacts, component: "Orchestrator")

            // Speak the content using TTS
            await speak(content)
        } else {
            lastResponse = "No phasing yet."

            // Speak the error message
            await speak(self.lastResponse)

            // List what files exist
            let files = artifactManager.listArtifacts()
            log("Current artifacts: \(files.joined(separator: ", "))", category: .artifacts, component: "Orchestrator")
        }
    }

    private func readSpecificPhase(_ phaseNumber: Int) async {
        if let phaseContent = artifactManager.readPhase(from: "phasing.md", phaseNumber: phaseNumber) {
            lastResponse = phaseContent
            log("Read phase \(phaseNumber) (\(phaseContent.count) chars)", category: .artifacts, component: "Orchestrator")

            // Speak the phase content using TTS
            await speak(phaseContent)
        } else {
            lastResponse = "Phase \(phaseNumber) not found."

            // Speak the error message
            await speak(self.lastResponse)
        }
    }

    private func editDescription(content: String) async {
        await editArtifact(type: .description, content: content, phaseNumber: nil)
    }

    private func editPhasing(phaseNumber: Int?, content: String) async {
        await editArtifact(type: .phasing, content: content, phaseNumber: phaseNumber)
    }

    private enum ArtifactType {
        case description
        case phasing

        var filename: String {
            switch self {
            case .description: return "description.md"
            case .phasing: return "phasing.md"
            }
        }

        var displayName: String {
            switch self {
            case .description: return "description"
            case .phasing: return "phasing"
            }
        }
    }

    private func editArtifact(type: ArtifactType, content: String, phaseNumber: Int?) async {
        lastResponse = "Updating \(type.displayName)..."

        do {
            // Add the edit request to conversation history as a requirement
            if type == .phasing, let phase = phaseNumber {
                addUserTranscript("Additional requirement for phase \(phase): \(content)")
            } else {
                addUserTranscript("Additional requirement for the \(type.displayName): \(content)")
            }

            // Regenerate the artifact with the new requirement included
            let updatedContent: String
            switch type {
            case .description:
                updatedContent = try await assistantClient.generateDescription(conversationHistory: conversationHistory)
            case .phasing:
                // For phasing edits, use multi-pass with status updates
                let statusCallback: ((String) -> Void)? = { [weak self] status in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.lastResponse = status
                        await self.speak(status)
                    }
                }
                updatedContent = try await assistantClient.generatePhasing(conversationHistory: conversationHistory, statusCallback: statusCallback)
            }

            // Save the regenerated artifact
            if artifactManager.safeWrite(filename: type.filename, content: updatedContent) {
                lastResponse = "\(type.displayName.capitalized) updated."
                await speak(self.lastResponse)
                addAssistantResponse("I've regenerated the \(type.displayName) with your new requirement.")
            } else {
                lastResponse = "Failed to update \(type.displayName)"
                await speak(self.lastResponse)
            }
        } catch {
            logError("Failed to regenerate \(type.displayName): \(error)", component: "Orchestrator")
            lastResponse = "Failed to regenerate \(type.displayName)"
            await speak(self.lastResponse)
        }
    }

    private func handleConversation(_ content: String) async {
        state = .conversing
        defer { state = .idle }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerContent = trimmedContent.lowercased()

        if let explicitQuery = extractSearchQuery(from: trimmedContent) {
            log("Detected inline search request: '\(explicitQuery)'", category: .search, component: "Orchestrator")
            // Determine depth based on content
            let depth: SearchDepth = lowerContent.contains("deep") || lowerContent.contains("research") ? .medium : .small
            await executeSearch(query: explicitQuery, depth: depth)
            return
        }

        // Removed auto-rerun search logic - was causing false positives

        do {
            // Generate conversational response
            let response = try await assistantClient.generateConversationalResponse(
                conversationHistory: conversationHistory
            )

            lastResponse = response

            // Speak the response
            await speak(response)

            // Add assistant response to history
            addAssistantResponse(response)
        } catch {
            logError("Failed to generate response: \(error)", component: "Orchestrator")
            lastResponse = "I couldn't process that. Try again?"

            // Speak the error
            await speak(self.lastResponse)
        }
    }

    private func extractSearchQuery(from content: String) -> String? {
        let patterns = [
            "search for",
            "look up",
            "find information about",
            "find info about",
            "find details about",
            "search the web for",
            "search the internet for",
            "can you search for",
            "please search for",
            "do a search for",
            "run a search for",
            "find out about"
        ]

        for pattern in patterns {
            if let range = content.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) {
                let queryStart = range.upperBound
                let rawQuery = content[queryStart...]
                let trimmedQuery = rawQuery
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,:;-"))

                if !trimmedQuery.isEmpty {
                    let lowerQuery = trimmedQuery.lowercased()
                    if !lowerQuery.hasPrefix("that") &&
                        !lowerQuery.hasPrefix("it") &&
                        !lowerQuery.hasPrefix("them") &&
                        !lowerQuery.hasPrefix("this") {
                        return trimmedQuery
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Error Handling

    private func handleGenerationError(_ error: Error, for artifact: String) -> String {
        logError("Failed to generate \(artifact): \(error)", component: "Orchestrator")

        let nsError = error as NSError

        // Check for network errors
        if nsError.domain == NSURLErrorDomain {
            return "Network error. Try again later."
        }

        // Check for API errors
        if nsError.domain == "NetworkManager" {
            switch nsError.code {
            case 429:
                return "Rate limit reached. Wait a moment."
            case 401:
                return "Authentication failed."
            default:
                return "API error. Try again."
            }
        }

        // Generic error
        return "Failed to generate \(artifact)."
    }

    // MARK: - TTS Control

    private func speak(_ text: String) async {
        // Log the AI response
        logAIResponse(text)

        #if canImport(UIKit)
        switch ttsProvider {
        case .elevenLabs:
            if let elevenLabs = elevenLabsTTS {
                do {
                    try await elevenLabs.synthesizeAndPlay(text)
                } catch {
                    logError("ElevenLabs TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await ttsManager.speak(text, interruptible: true)
                }
            } else {
                await ttsManager.speak(text, interruptible: true)
            }
        case .groq:
            if let groqTTS = groqTTSManager {
                do {
                    try await groqTTS.synthesizeAndPlay(text)
                } catch {
                    logError("Groq TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await ttsManager.speak(text, interruptible: true)
                }
            } else {
                await ttsManager.speak(text, interruptible: true)
            }
        case .deepInfra:
            if let deepInfra = deepInfraTTS {
                do {
                    try await deepInfra.synthesizeAndPlay(text)
                } catch {
                    logError("DeepInfra TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await ttsManager.speak(text, interruptible: true)
                }
            } else {
                await ttsManager.speak(text, interruptible: true)
            }
        case .lowLatency:
            if let lowLatency = lowLatencyTTS {
                await lowLatency.speak(text)
            } else {
                // Fallback to native
                await ttsManager.speak(text, interruptible: true)
            }
        case .native:
            await ttsManager.speak(text, interruptible: true)
        }
        #else
        // macOS/testing: always use provided TTS manager
        await ttsManager.speak(text, interruptible: true)
        #endif
    }

    func stopSpeaking() {
        #if canImport(UIKit)
        switch ttsProvider {
        case .elevenLabs:
            elevenLabsTTS?.stop()
        case .groq:
            groqTTSManager?.stop()
        case .deepInfra:
            deepInfraTTS?.stop()
        case .lowLatency:
            lowLatencyTTS?.stop()
        case .native:
            ttsManager.stop()
        }
        #else
        ttsManager.stop()
        #endif
    }

    // MARK: - Context Management

    func addUserTranscript(_ transcript: String) {
        conversationHistory.append((role: "user", content: transcript))

        // Keep conversation history within limit for extensive context
        let historyLimit = 100
        if conversationHistory.count > historyLimit {
            conversationHistory = Array(conversationHistory.suffix(historyLimit))
        }
    }

    func addAssistantResponse(_ response: String) {
        conversationHistory.append((role: "assistant", content: response))
    }

    func recentConversationContext(limit: Int = 6) -> [String] {
        let slice = conversationHistory.suffix(limit)
        return slice.map { entry in
            "\(entry.role.capitalized): \(entry.content)"
        }
    }

    func currentSearchQuery() -> String? {
        lastSearchQuery
    }

    // MARK: - Content Processing

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

    // MARK: - Clipboard Operations

    func copyDescriptionToClipboard() -> Bool {
        guard let content = artifactManager.safeRead(filename: "description.md") else {
            lastResponse = "No description to copy. Say 'write the description' first."
            return false
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #endif
        lastResponse = "Description copied to clipboard!"
        return true
    }

    func copyPhasingToClipboard() -> Bool {
        guard let content = artifactManager.safeRead(filename: "phasing.md") else {
            lastResponse = "No phasing to copy. Say 'write the phasing' first."
            return false
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = content
        #endif
        lastResponse = "Phasing copied to clipboard!"
        return true
    }

    func copyBothToClipboard() -> Bool {
        let description = artifactManager.safeRead(filename: "description.md") ?? ""
        let phasing = artifactManager.safeRead(filename: "phasing.md") ?? ""

        guard !description.isEmpty || !phasing.isEmpty else {
            lastResponse = "No artifacts to copy. Write them first."
            return false
        }

        var combined = ""
        if !description.isEmpty {
            combined += description + "\n\n"
        }
        if !phasing.isEmpty {
            combined += "---\n\n" + phasing
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = combined
        #endif
        lastResponse = "Both artifacts copied to clipboard!"
        return true
    }

    // MARK: - Search Sound Feedback

    private func playSearchStartSound() {
        #if canImport(AudioToolbox)
        // Tink sound - gentle start
        AudioServicesPlaySystemSound(1057)
        #endif
    }

}
