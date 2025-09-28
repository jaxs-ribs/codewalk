import Foundation
import Combine
import UIKit
import AudioToolbox

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
    private let ttsManager: TTSManager
    private let groqTTSManager: GroqTTSManager?
    private let elevenLabsTTS: ElevenLabsTTS?
    private let ttsProvider: TTSProvider
    private var searchService: SearchService?  // For Phase 1 testing
    private var searchSoundTimer: Timer?  // Timer for search feedback sounds
    private var lastSearchQuery: String?

    init(config: EnvConfig) {
        // Initialize artifact manager
        artifactManager = ArtifactManager()

        // Initialize assistant client
        assistantClient = AssistantClient(groqApiKey: config.groqApiKey)

        // Initialize TTS manager (iOS native)
        ttsManager = TTSManager()

        // Determine TTS provider from launch arguments
        if CommandLine.arguments.contains("--UseElevenLabs") {
            ttsProvider = .elevenLabs
            elevenLabsTTS = ElevenLabsTTS(apiKey: config.elevenLabsApiKey)
            groqTTSManager = nil
            log("Using ElevenLabs TTS", category: .tts, component: "Orchestrator")
        } else if CommandLine.arguments.contains("--UseGroqTTS") {
            ttsProvider = .groq
            groqTTSManager = GroqTTSManager(groqApiKey: config.groqApiKey)
            elevenLabsTTS = nil
            log("Using Groq TTS with PlayAI voices", category: .tts, component: "Orchestrator")
        } else {
            ttsProvider = .native
            groqTTSManager = nil
            elevenLabsTTS = nil
            log("Using iOS native TTS", category: .tts, component: "Orchestrator")
        }

        log("Initialized with ArtifactManager, AssistantClient, and TTS", category: .system, component: "Orchestrator")

        // Initialize SearchService if Brave API key is available (Phase 1 testing)
        if !config.braveApiKey.isEmpty {
            searchService = SearchService(config: config)
            log("SearchService initialized", category: .system, component: "Orchestrator")
        }
    }

    // MARK: - Phase 1 Test Method

    func testSearch(query: String) async {
        guard let searchService = searchService else {
            logError("SearchService not initialized. Check BRAVE_API_KEY in .env", component: "Orchestrator")
            lastResponse = "Search service not available"
            return
        }

        print("[Orchestrator] TEST: Starting search for '\(query)'")
        lastResponse = "Searching for \(query)..."

        do {
            let summary = try await searchService.search(query: query)
            print("[Orchestrator] TEST: Search successful!")
            print("[Orchestrator] TEST: Summary (\(summary.count) chars): \(summary.prefix(200))...")
            lastResponse = summary

            // Test TTS with the summary
            await speak(summary)
        } catch {
            print("[Orchestrator] TEST: Search failed - \(error)")
            lastResponse = "Search failed: \(error.localizedDescription)"
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
        case .nextPhase:
            lastResponse = "Next phase"
        case .previousPhase:
            lastResponse = "Previous phase"
        case .stop:
            lastResponse = "Stopped"
        case .copyDescription:
            await copyDescriptionAction()
        case .copyPhasing:
            await copyPhasingAction()
        case .copyBoth:
            await copyBothAction()
        case .search(let query):
            await executeSearch(query: query)
        }
    }

    // MARK: - Search Execution

    private func executeSearch(query: String) async {
        guard let searchService = searchService else {
            lastResponse = "Search service not available. Check BRAVE_API_KEY in .env"
            await speak(lastResponse)
            return
        }

        log("Executing search for: '\(query)'", category: .search, component: "Orchestrator")
        lastSearchQuery = query
        lastResponse = "Searching for \(query)..."
        await speak("Searching for \(query)...")

        // Start search with tick sounds
        playSearchTickSound()  // Initial tick
        startSearchSoundTimer()

        do {
            let summary = try await searchService.search(query: query)
            logSuccess("Search successful, summary: \(summary.count) chars", component: "Orchestrator")
            lastResponse = summary

            // Stop search sounds (no completion chime)
            stopSearchSoundTimer()

            // Add search result to conversation history
            addUserTranscript("Search for: \(query)")
            addAssistantResponse(summary)

            // Speak the search results
            await speak(summary)
        } catch {
            logError("Search failed: \(error)", component: "Orchestrator")
            lastResponse = "Search failed: \(error.localizedDescription)"

            // Stop search sounds (no error sound)
            stopSearchSoundTimer()

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
            let content = try await generateContent(for: type)

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

    private func generateContent(for type: ArtifactType) async throws -> String {
        switch type {
        case .description:
            return try await assistantClient.generateDescription(
                conversationHistory: conversationHistory
            )
        case .phasing:
            return try await assistantClient.generatePhasing(
                conversationHistory: conversationHistory
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
            // Log first 100 chars for display
            let preview = String(content.prefix(100))
            lastResponse = "Reading description..."
            print("[Orchestrator] Read description (\(content.count) chars)")

            // Speak the content using TTS
            await speak(content)
        } else {
            lastResponse = "No description yet."

            // Speak the error message
            await speak(self.lastResponse)

            // List what files exist
            let files = artifactManager.listArtifacts()
            print("[Orchestrator] Current artifacts: \(files.joined(separator: ", "))")
        }
    }

    private func readPhasing() async {
        if let content = artifactManager.safeRead(filename: "phasing.md") {
            // Log first 100 chars for display
            let preview = String(content.prefix(100))
            lastResponse = "Reading phasing..."
            print("[Orchestrator] Read phasing (\(content.count) chars)")

            // Speak the content using TTS
            await speak(content)
        } else {
            lastResponse = "No phasing yet."

            // Speak the error message
            await speak(self.lastResponse)

            // List what files exist
            let files = artifactManager.listArtifacts()
            print("[Orchestrator] Current artifacts: \(files.joined(separator: ", "))")
        }
    }

    private func readSpecificPhase(_ phaseNumber: Int) async {
        if let phaseContent = artifactManager.readPhase(from: "phasing.md", phaseNumber: phaseNumber) {
            lastResponse = phaseContent
            print("[Orchestrator] Read phase \(phaseNumber) (\(phaseContent.count) chars)")

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
                updatedContent = try await assistantClient.generatePhasing(conversationHistory: conversationHistory)
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
            print("[Orchestrator] Failed to regenerate \(type.displayName): \(error)")
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
            print("[Orchestrator] Detected inline search request: '\(explicitQuery)'")
            await executeSearch(query: explicitQuery)
            return
        }

        if shouldReuseLastSearch(for: lowerContent), let query = lastSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            print("[Orchestrator] Re-running last search for conversation follow-up: '\(query)'")
            await executeSearch(query: query)
            return
        }

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
            print("[Orchestrator] Failed to generate response: \(error)")
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

    private func shouldReuseLastSearch(for lowerContent: String) -> Bool {
        guard lastSearchQuery != nil else { return false }

        let searchVerbs = ["search", "look", "find"]
        let pronouns = ["that", "it", "them", "this", "previous", "same"]

        let containsVerb = searchVerbs.contains { lowerContent.contains($0) }
        let containsPronoun = pronouns.contains { lowerContent.contains($0) }
        let containsRetry = lowerContent.contains("again") || lowerContent.contains("another") || lowerContent.contains("fresh") || lowerContent.contains("new") || lowerContent.contains("live")

        return containsVerb && (containsPronoun || containsRetry)
    }

    // MARK: - Error Handling

    private func handleGenerationError(_ error: Error, for artifact: String) -> String {
        print("[Orchestrator] Failed to generate \(artifact): \(error)")

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

        switch ttsProvider {
        case .elevenLabs:
            if let elevenLabs = elevenLabsTTS {
                do {
                    try await elevenLabs.synthesizeAndPlay(text)
                } catch {
                    logError("ElevenLabs TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await MainActor.run {
                        self.ttsManager.speak(text)
                    }
                }
            } else {
                await MainActor.run {
                    self.ttsManager.speak(text)
                }
            }
        case .groq:
            if let groqTTS = groqTTSManager {
                do {
                    try await groqTTS.synthesizeAndPlay(text)
                } catch {
                    logError("Groq TTS failed, falling back to iOS TTS: \(error)", component: "TTS")
                    // Fallback to iOS TTS
                    await MainActor.run {
                        self.ttsManager.speak(text)
                    }
                }
            } else {
                await MainActor.run {
                    self.ttsManager.speak(text)
                }
            }
        case .native:
            await MainActor.run {
                self.ttsManager.speak(text)
            }
        }
    }

    func stopSpeaking() {
        switch ttsProvider {
        case .elevenLabs:
            elevenLabsTTS?.stop()
        case .groq:
            groqTTSManager?.stop()
        case .native:
            ttsManager.stop()
        }
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

    // MARK: - Clipboard Operations

    func copyDescriptionToClipboard() -> Bool {
        guard let content = artifactManager.safeRead(filename: "description.md") else {
            lastResponse = "No description to copy. Say 'write the description' first."
            return false
        }

        UIPasteboard.general.string = content
        lastResponse = "Description copied to clipboard!"
        return true
    }

    func copyPhasingToClipboard() -> Bool {
        guard let content = artifactManager.safeRead(filename: "phasing.md") else {
            lastResponse = "No phasing to copy. Say 'write the phasing' first."
            return false
        }

        UIPasteboard.general.string = content
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

        UIPasteboard.general.string = combined
        lastResponse = "Both artifacts copied to clipboard!"
        return true
    }

    // MARK: - Search Sound Feedback

    private func playSearchStartSound() {
        // Tink sound - gentle start
        AudioServicesPlaySystemSound(1057)
    }

    private func playSearchTickSound() {
        // Keyboard tap sound - much more pleasant than 1103
        AudioServicesPlaySystemSound(1057)
    }

    private func playSearchCompleteSound() {
        // Success chime
        AudioServicesPlaySystemSound(1025)
    }

    private func playSearchErrorSound() {
        // Error/failure sound
        AudioServicesPlaySystemSound(1053)
    }

    private func startSearchSoundTimer() {
        // Stop any existing timer
        stopSearchSoundTimer()

        // Play tick sound every 1.5 seconds
        searchSoundTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.playSearchTickSound()
        }
    }

    private func stopSearchSoundTimer() {
        searchSoundTimer?.invalidate()
        searchSoundTimer = nil
    }
}
