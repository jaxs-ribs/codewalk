import Foundation
import Combine
import UIKit

// MARK: - Orchestrator State

enum OrchestratorState {
    case idle
    case conversing
    case executing
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
    private let useGroqTTS: Bool

    init(groqApiKey: String) {
        // Initialize artifact manager
        artifactManager = ArtifactManager()

        // Initialize assistant client
        assistantClient = AssistantClient(groqApiKey: groqApiKey)

        // Initialize TTS manager (iOS native)
        ttsManager = TTSManager()

        // Check for Groq TTS preference via launch arguments
        useGroqTTS = CommandLine.arguments.contains("--UseGroqTTS")

        // Initialize Groq TTS if enabled
        if useGroqTTS {
            groqTTSManager = GroqTTSManager(groqApiKey: groqApiKey)
            print("[Orchestrator] Using Groq TTS with PlayAI voices")
        } else {
            groqTTSManager = nil
            print("[Orchestrator] Using iOS native TTS")
        }

        print("[Orchestrator] Initialized with ArtifactManager, AssistantClient, and TTS")
    }

    // MARK: - Queue Management

    func enqueueAction(_ action: ProposedAction) {
        print("[Orchestrator] Enqueueing action: \(action)")

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

        print("[Orchestrator] Processing queue with \(actionQueue.count) items")

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
        print("[Orchestrator] Executing action: \(action)")

        switch action {
        case .writeDescription:
            await writeDescription()
        case .writePhasing:
            await writePhasing()
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
        lastResponse = "Writing description..."

        do {
            // Generate content based on conversation history
            let content = try await assistantClient.generateDescription(
                conversationHistory: conversationHistory
            )

            if artifactManager.safeWrite(filename: "description.md", content: content) {
                lastResponse = "Description written."

                // Speak the success message
                await speak(self.lastResponse)

                // Add to conversation history
                addAssistantResponse("I've written the project description based on our conversation.")
            } else {
                lastResponse = "Failed to write description"

                // Speak the error
                await speak(self.lastResponse)
            }
        } catch {
            lastResponse = handleGenerationError(error, for: "description")
            await speak(self.lastResponse)
        }
    }

    private func writePhasing() async {
        lastResponse = "Writing phasing..."

        do {
            // Generate content based on conversation history
            let content = try await assistantClient.generatePhasing(
                conversationHistory: conversationHistory
            )

            if artifactManager.safeWrite(filename: "phasing.md", content: content) {
                lastResponse = "Phasing written."

                // Speak the success message
                await speak(self.lastResponse)

                // Add to conversation history
                addAssistantResponse("I've written the project phasing based on our conversation.")
            } else {
                lastResponse = "Failed to write phasing"

                // Speak the error
                await speak(self.lastResponse)
            }
        } catch {
            lastResponse = handleGenerationError(error, for: "phasing")
            await speak(self.lastResponse)
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
            lastResponse = "Reading phase \(phaseNumber)..."
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

        state = .idle
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
        if useGroqTTS, let groqTTS = groqTTSManager {
            do {
                try await groqTTS.synthesizeAndPlay(text)
            } catch {
                print("[Orchestrator] Groq TTS failed, falling back to iOS: \(error)")
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
    }

    func stopSpeaking() {
        if useGroqTTS {
            groqTTSManager?.stop()
        } else {
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
}