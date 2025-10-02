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
}

// MARK: - Action Queue Item

struct ActionQueueItem {
    let action: ToolAction
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

    #if canImport(UIKit)
    private let groqTTSManager: GroqTTSManager?
    private let elevenLabsTTS: ElevenLabsTTS?
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

        // Router removed in favor of ToolAction planning

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

    func enqueueAction(_ action: ToolAction) {
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

        // Plan a tool action from context
        do {
            let (desc, phasing) = artifactManager.readSpec()
            let action = try await assistantClient.planToolAction(
                userQuery: text,
                conversationHistory: conversationHistory,
                specDescription: desc,
                specPhasing: phasing
            )
            enqueueAction(action)

            // Wait for completion
            await waitForCompletion()
        } catch {
            logError("Test mode: planning failed: \(error)", component: "Orchestrator")
            lastResponse = "Planning failed: \(error.localizedDescription)"
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

    private func executeAction(_ action: ToolAction) async {
        log("Executing tool action: \(action)", category: .orchestrator)

        switch action {
        case .extract(let text):
            lastResponse = text
            addAssistantResponse(text)
            // Do not block the queue on long speech; allow interrupts
            Task { @MainActor [weak self] in
                await self?.speak(text)
            }

        case .overwrite(let artifact, let content):
            let ok = artifactManager.overwrite(artifact: artifact, content: content)
            lastResponse = ok ? "Updated \(artifact)." : "Failed to update \(artifact)."
            addAssistantResponse(lastResponse)
            Task { @MainActor [weak self] in
                await self?.speak(self?.lastResponse ?? "")
            }

        case .writeDiff(let artifact, let diff, let fallback):
            let ok = artifactManager.applyUnifiedDiff(artifact: artifact, diff: diff, fallbackContent: fallback)
            lastResponse = ok ? "Changes applied to \(artifact)." : "Failed to apply changes to \(artifact)."
            addAssistantResponse(lastResponse)
            Task { @MainActor [weak self] in
                await self?.speak(self?.lastResponse ?? "")
            }

        case .search(let query, let depth):
            let d: SearchDepth = (depth == "deep") ? .medium : .small
            await executeSearch(query: query, depth: d)

        case .copy(let artifact):
            switch artifact.lowercased() {
            case "spec", "both":
                _ = copyBothToClipboard()
            case "description":
                _ = copyDescriptionToClipboard()
            case "phasing":
                _ = copyPhasingToClipboard()
            default:
                lastResponse = "Unknown artifact to copy."
            }
            addAssistantResponse(lastResponse)
            Task { @MainActor [weak self] in
                await self?.speak(self?.lastResponse ?? "")
            }
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

    // MARK: - Unified Write Handler (Phase 3)

    private func executeWrite(artifact: String, instructions: String?) async {
        // Determine the artifact type
        let artifactLower = artifact.lowercased()

        // Handle spec/both - write both description and phasing
        if artifactLower == "spec" || artifactLower == "both" {
            if instructions != nil {
                // Edit both with instructions
                await executeWrite(artifact: "description", instructions: instructions)
                await executeWrite(artifact: "phasing", instructions: instructions)
            } else {
                // Create both from conversation history
                await speak("Writing description...")
                await generateAndWriteDescription()
                await speak("Writing phasing...")
                await generateAndWritePhasing()
                lastResponse = "Description and phasing written."
            }
            return
        }

        // Determine if this is description or phasing
        guard artifactLower == "description" || artifactLower == "phasing" else {
            lastResponse = "Unknown artifact: \(artifact)"
            await speak(lastResponse)
            return
        }

        let isDescription = artifactLower == "description"
        let displayName = isDescription ? "description" : "phasing"

        // Check if file exists to determine create vs edit
        let (existingDescription, existingPhasing) = artifactManager.readSpec()
        let fileExists = (isDescription && existingDescription != nil) ||
                        (!isDescription && existingPhasing != nil)

        // If we have instructions, this is an edit/transform operation
        if let inst = instructions, !inst.isEmpty {
            // Special handling for phasing operations
            if !isDescription {
                let lowerInst = inst.lowercased()

                // Check for merge operation
                if lowerInst.contains("merge") {
                    if let range = extractPhaseRange(from: inst) {
                        await performMergePhases(range.start, endPhase: range.end, instructions: inst)
                        return
                    }
                }

                // Check for split operation
                if lowerInst.contains("split") {
                    if let phaseNum = extractPhaseNumber(from: inst) {
                        await performSplitPhase(phaseNum, instructions: inst)
                        return
                    }
                }

                // Check for specific phase edit
                if let phaseNum = extractPhaseNumber(from: inst) {
                    // Edit specific phase
                    await performEditPhase(phaseNum, instructions: inst)
                    return
                }
            }

            // General edit - regenerate with instructions
            addUserTranscript("Additional requirement for the \(displayName): \(inst)")

            if isDescription {
                await generateAndWriteDescription()
            } else {
                await generateAndWritePhasing()
            }

        } else {
            // No instructions - pure create from conversation history
            lastResponse = "Writing \(displayName)..."
            await speak(lastResponse)

            if isDescription {
                await generateAndWriteDescription()
            } else {
                await generateAndWritePhasing()
            }
        }
    }

    // Helper methods for writing artifacts
    private func generateAndWriteDescription() async {
        do {
            let content = try await assistantClient.generateDescription(
                conversationHistory: conversationHistory
            )

            if artifactManager.writeSpecDescription(content) {
                lastResponse = "Description written."
                addAssistantResponse("I've written the project description based on our conversation.")
                await speak(lastResponse)
            } else {
                lastResponse = "Failed to write description"
                await speak(lastResponse)
            }
        } catch {
            lastResponse = handleGenerationError(error, for: "description")
            await speak(lastResponse)
        }
    }

    private func generateAndWritePhasing() async {
        do {
            // Use multi-pass generation with status updates
            let statusCallback: ((String) -> Void) = { [weak self] status in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.lastResponse = status
                    await self.speak(status)
                }
            }

            let content = try await assistantClient.generatePhasing(
                conversationHistory: conversationHistory,
                statusCallback: statusCallback
            )

            if artifactManager.writeSpecPhasing(content) {
                lastResponse = "Phasing written."
                addAssistantResponse("I've written the project phasing based on our conversation.")
                await speak(lastResponse)
            } else {
                lastResponse = "Failed to write phasing"
                await speak(lastResponse)
            }
        } catch {
            lastResponse = handleGenerationError(error, for: "phasing")
            await speak(lastResponse)
        }
    }

    private func performEditPhase(_ phaseNumber: Int, instructions: String) async {
        guard let config = try? EnvConfig.load() else {
            lastResponse = "Failed to load configuration for phase editing"
            await speak(lastResponse)
            return
        }

        await speak("Editing phase \(phaseNumber)...")

        let success = await artifactManager.editSpecificPhase(phaseNumber, instructions: instructions, groqApiKey: config.groqApiKey)

        if success {
            lastResponse = "Phase \(phaseNumber) updated."
            await speak(lastResponse)
            addAssistantResponse("I've updated phase \(phaseNumber) based on your instructions: \(instructions)")
        } else {
            lastResponse = "Failed to update phase \(phaseNumber)"
            await speak(lastResponse)
        }
    }

    private func performSplitPhase(_ phaseNumber: Int, instructions: String) async {
        lastResponse = "Splitting phase \(phaseNumber)..."
        await speak(lastResponse)

        guard let config = try? EnvConfig.load() else {
            lastResponse = "Failed to load configuration for phase splitting"
            await speak(lastResponse)
            return
        }

        let success = await artifactManager.splitPhase(phaseNumber, instructions: instructions, groqApiKey: config.groqApiKey)

        if success {
            lastResponse = "Phase \(phaseNumber) split successfully."
            await speak(lastResponse)
            addAssistantResponse("I've split phase \(phaseNumber) based on your instructions: \(instructions)")
        } else {
            lastResponse = "Failed to split phase \(phaseNumber)"
            await speak(lastResponse)
        }
    }

    private func performMergePhases(_ startPhase: Int, endPhase: Int, instructions: String?) async {
        lastResponse = "Merging phases \(startPhase) through \(endPhase)..."
        await speak(lastResponse)

        guard let config = try? EnvConfig.load() else {
            lastResponse = "Failed to load configuration for phase merging"
            await speak(lastResponse)
            return
        }

        let success = await artifactManager.mergePhases(startPhase, endPhase, instructions: instructions, groqApiKey: config.groqApiKey)

        if success {
            lastResponse = "Phases merged successfully."
            await speak(lastResponse)
            addAssistantResponse("I've merged phases \(startPhase) through \(endPhase)")
        } else {
            let phaseCount = endPhase - startPhase + 1
            if phaseCount > 5 {
                lastResponse = "Cannot merge \(phaseCount) phases at once. Try merging up to 5 phases instead."
            } else {
                lastResponse = "Failed to merge phases. Check that phases \(startPhase) through \(endPhase) exist."
            }
            await speak(lastResponse)
        }
    }

    // Helper methods for phase extraction
    private func extractPhaseNumber(from text: String) -> Int? {
        let patterns = [
            "phase\\s+(\\d+)",
            "(\\d+)\\s*phase",
            "phase\\s+([a-z]+)",
            "#(\\d+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    let captured = String(text[range])

                    // Handle word numbers
                    let wordToNum = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                                     "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
                    if let num = wordToNum[captured.lowercased()] {
                        return num
                    }

                    // Handle numeric
                    if let num = Int(captured) {
                        return num
                    }
                }
            }
        }
        return nil
    }

    private func extractPhaseRange(from text: String) -> (start: Int, end: Int)? {
        // Normalize dashes and case
        let normalized = text
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .lowercased()

        // Try numeric patterns first
        let numPatterns = [
            "phases?\\s+(\\d+)\\s*(?:to|through|thru|-)\\s*(\\d+)",
            "(\\d+)\\s*(?:to|through|thru|-)\\s*(\\d+)"
        ]
        for pattern in numPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                if let r1 = Range(match.range(at: 1), in: normalized),
                   let r2 = Range(match.range(at: 2), in: normalized),
                   let start = Int(normalized[r1]),
                   let end = Int(normalized[r2]) {
                    return (start, end)
                }
            }
        }

        // Word-number ranges (e.g., "phases two to four")
        let wordToNum: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
        ]
        let wordPatterns = [
            "phases?\\s+([a-z]+)\\s*(?:to|through|thru|-)\\s*([a-z]+)",
            "([a-z]+)\\s*(?:to|through|thru|-)\\s*([a-z]+)"
        ]
        for pattern in wordPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                if let r1 = Range(match.range(at: 1), in: normalized),
                   let r2 = Range(match.range(at: 2), in: normalized) {
                    let s = String(normalized[r1])
                    let e = String(normalized[r2])
                    if let start = wordToNum[s], let end = wordToNum[e] {
                        return (start, end)
                    }
                }
            }
        }

        // Conjunction variant
        if let regex = try? NSRegularExpression(pattern: "phases?\\s+(\\d+)\\s*and\\s*(\\d+)", options: .caseInsensitive),
           let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let r1 = Range(match.range(at: 1), in: normalized),
           let r2 = Range(match.range(at: 2), in: normalized),
           let start = Int(normalized[r1]), let end = Int(normalized[r2]) {
            return (start, end)
        }

        return nil
    }

    // MARK: - Unified Read Handler (Phase 4)

    private func executeRead(artifact: String, scope: String?) async {
        let artifactLower = artifact.lowercased()

        // Use the last user message as the request for context-aware reading
        let userQuery = conversationHistory.last { $0.role == "user" }?.content ?? "read"

        // Load spec context
        let (specDescription, specPhasing) = artifactManager.readSpec()

        if specDescription == nil && specPhasing == nil {
            lastResponse = "No spec yet."
            await speak(lastResponse)
            return
        }

        // Provide a soft hint to the model, but let it decide
        var preferred: String? = nil
        let uqLower = userQuery.lowercased()
        if uqLower.contains("read the spec") || uqLower.contains("read the whole thing") || uqLower.contains("read everything") || uqLower.contains("read me everything") {
            preferred = "Read the full spec: description then phasing."
        }
        switch artifactLower {
        case "spec", "both":
            preferred = "Read the full spec: description then phasing."
        case "description":
            preferred = "Read the Project Description section."
        case "phasing":
            preferred = scope?.isEmpty == false ? "Focus on the requested phases if possible." : "Read the Project Phasing section."
        default:
            break
        }

        // Ask the model to select the right content from the spec
        do {
            let content = try await assistantClient.generateReadFromSpec(
                specDescription: specDescription,
                specPhasing: specPhasing,
                userQuery: userQuery,
                preferred: preferred
            )
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lastResponse = trimmed
                log("Generated read content (\(trimmed.count) chars)", category: .artifacts, component: "Orchestrator")
                await speak(trimmed)
                return
            }
        } catch {
            logError("Context read generation failed: \(error)", component: "Orchestrator")
        }

        // Fallback direct reads if generation failed
        if artifactLower == "spec" || artifactLower == "both" {
            if let desc = specDescription, !desc.isEmpty { await speak(desc) } else { await speak("No description yet.") }
            if let ph = specPhasing, !ph.isEmpty { await speak(ph) } else { await speak("No phasing yet.") }
            return
        }
        if artifactLower == "description" {
            if let desc = specDescription, !desc.isEmpty {
                lastResponse = desc
                await speak(desc)
            } else {
                lastResponse = "No description yet."
                await speak(lastResponse)
            }
            return
        }
        if artifactLower == "phasing" {
            if let ph = specPhasing, !ph.isEmpty {
                lastResponse = ph
                await speak(ph)
            } else {
                lastResponse = "No phasing yet."
                await speak(lastResponse)
            }
            return
        }

        lastResponse = "Unknown artifact: \(artifact)"
        await speak(lastResponse)
    }

    private func readPhaseRange(start: Int, end: Int) async {
        let (_, phasing) = artifactManager.readSpec()
        guard let phasingContent = phasing else {
            lastResponse = "No phasing yet."
            await speak(lastResponse)
            return
        }

        // Parse phases from the phasing content
        let phases = PhaseParser.parsePhases(from: phasingContent)
        let matchingPhases = phases.filter { $0.number >= start && $0.number <= end }

        if matchingPhases.isEmpty {
            lastResponse = "Phases \(start) through \(end) not found."
            await speak(lastResponse)
            return
        }

        // Build combined text for all phases in range
        var combinedText = "Reading phases \(start) through \(end):\n\n"
        for phase in matchingPhases {
            combinedText += "## Phase \(phase.number): \(phase.title)\n\n"
            combinedText += "\(phase.description)\n\n"
            combinedText += "**Definition of Done:** \(phase.definitionOfDone)\n\n"
        }

        lastResponse = combinedText
        log("Read phases \(start)-\(end) (\(combinedText.count) chars)", category: .artifacts, component: "Orchestrator")
        await speak(combinedText)
    }

    // MARK: - Artifact Operations (Phase 3 - Unified Write Handler)

    private func writeDescription() async {
        await executeWrite(artifact: "description", instructions: nil)
    }

    private func writePhasing() async {
        await executeWrite(artifact: "phasing", instructions: nil)
    }

    private func writeDescriptionAndPhasing() async {
        await executeWrite(artifact: "both", instructions: nil)
    }

    // Legacy writeArtifact methods removed in Phase 5 - functionality moved to executeWrite()

    private func readDescription() async {
        await executeRead(artifact: "description", scope: nil)
    }

    private func readPhasing() async {
        await executeRead(artifact: "phasing", scope: nil)
    }

    private func readSpecificPhase(_ phaseNumber: Int) async {
        // Direct implementation to avoid recursion with executeRead
        let (_, phasing) = artifactManager.readSpec()
        if let phasingContent = phasing {
            // Parse phases from the phasing content
            let phases = PhaseParser.parsePhases(from: phasingContent)
            if let phase = phases.first(where: { $0.number == phaseNumber }) {
                let phaseText = "## Phase \(phase.number): \(phase.title)\n\n\(phase.description)\n\n**Definition of Done:** \(phase.definitionOfDone)"
                lastResponse = phaseText
                log("Read phase \(phaseNumber) (\(phaseText.count) chars)", category: .artifacts, component: "Orchestrator")

                // Speak the phase content using TTS
                await speak(phaseText)
            } else {
                lastResponse = "Phase \(phaseNumber) not found."

                // Speak the error message
                await speak(lastResponse)
            }
        } else {
            lastResponse = "No phasing yet."

            // Speak the error message
            await speak(lastResponse)
        }
    }

    private func editDescription(content: String) async {
        await executeWrite(artifact: "description", instructions: content)
    }

    private func editPhasing(phaseNumber: Int?, content: String) async {
        if let phase = phaseNumber {
            await executeWrite(artifact: "phasing", instructions: "edit phase \(phase): \(content)")
        } else {
            await executeWrite(artifact: "phasing", instructions: content)
        }
    }

    private func splitPhase(_ phaseNumber: Int, instructions: String) async {
        await executeWrite(artifact: "phasing", instructions: "split phase \(phaseNumber): \(instructions)")
    }

    private func mergePhases(_ startPhase: Int, endPhase: Int, instructions: String?) async {
        let mergeInstructions = if let inst = instructions {
            "merge phases \(startPhase) through \(endPhase): \(inst)"
        } else {
            "merge phases \(startPhase) through \(endPhase)"
        }
        await executeWrite(artifact: "phasing", instructions: mergeInstructions)
    }

    // Legacy methods removed in Phase 5 - all operations now use unified handlers

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
        let (description, _) = artifactManager.readSpec()
        guard let content = description else {
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
        let (_, phasing) = artifactManager.readSpec()
        guard let content = phasing else {
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
        // Use spec.md directly if it exists, otherwise combine sections
        if let specContent = artifactManager.safeRead(filename: "spec.md") {
            #if canImport(UIKit)
            UIPasteboard.general.string = specContent
            #endif
            lastResponse = "Spec copied to clipboard!"
            return true
        }

        // Fallback to reading individual sections from spec
        let (description, phasing) = artifactManager.readSpec()

        guard description != nil || phasing != nil else {
            lastResponse = "No artifacts to copy. Write them first."
            return false
        }

        var combined = ""
        if let desc = description {
            combined += desc + "\n\n"
        }
        if let phase = phasing {
            if !combined.isEmpty {
                combined += "---\n\n"
            }
            combined += phase
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
