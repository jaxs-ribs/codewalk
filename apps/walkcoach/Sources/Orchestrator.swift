import Foundation
import Combine

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

    init(groqApiKey: String) {
        // Initialize artifact manager
        artifactManager = ArtifactManager()

        // Initialize assistant client
        assistantClient = AssistantClient(groqApiKey: groqApiKey)

        print("[Orchestrator] Initialized with ArtifactManager and AssistantClient")
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
        case .editDescription(let content):
            await editDescription(content: content)
        case .editPhasing(let phaseNumber, let content):
            await editPhasing(phaseNumber: phaseNumber, content: content)
        case .conversation(let content):
            await handleConversation(content)
        case .clarification(let question):
            lastResponse = question
        case .repeatLast:
            // Already displayed in lastResponse
            break
        case .nextPhase:
            lastResponse = "Next phase navigation coming in Phase 7"
        case .previousPhase:
            lastResponse = "Previous phase navigation coming in Phase 7"
        case .stop:
            lastResponse = "Stopped"
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
                lastResponse = "Description written. Say 'read the description' to hear it."

                // Add to conversation history
                addAssistantResponse("I've written the project description based on our conversation.")
            } else {
                lastResponse = "Failed to write description"
            }
        } catch {
            print("[Orchestrator] Failed to generate description: \(error)")
            lastResponse = "Failed to generate description"
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
                lastResponse = "Phasing written. Say 'read the phasing' to hear it."

                // Add to conversation history
                addAssistantResponse("I've written the project phasing based on our conversation.")
            } else {
                lastResponse = "Failed to write phasing"
            }
        } catch {
            print("[Orchestrator] Failed to generate phasing: \(error)")
            lastResponse = "Failed to generate phasing"
        }
    }

    private func readDescription() async {
        if let content = artifactManager.safeRead(filename: "description.md") {
            // Log first 100 chars for display
            let preview = String(content.prefix(100))
            lastResponse = "Reading description: \(preview)..."
            print("[Orchestrator] Read description (\(content.count) chars)")
            // Phase 7 will add TTS here
        } else {
            lastResponse = "No description yet. Say 'write the description' first."

            // List what files exist
            let files = artifactManager.listArtifacts()
            print("[Orchestrator] Current artifacts: \(files.joined(separator: ", "))")
        }
    }

    private func readPhasing() async {
        if let content = artifactManager.safeRead(filename: "phasing.md") {
            // Log first 100 chars for display
            let preview = String(content.prefix(100))
            lastResponse = "Reading phasing: \(preview)..."
            print("[Orchestrator] Read phasing (\(content.count) chars)")
            // Phase 7 will add TTS here
        } else {
            lastResponse = "No phasing yet. Say 'write the phasing' first."

            // List what files exist
            let files = artifactManager.listArtifacts()
            print("[Orchestrator] Current artifacts: \(files.joined(separator: ", "))")
        }
    }

    private func editDescription(content: String) async {
        lastResponse = "Editing description..."

        if artifactManager.appendToFile(filename: "description.md", content: "\n\(content)") {
            lastResponse = "Description updated"
        } else {
            lastResponse = "Failed to edit description"
        }
    }

    private func editPhasing(phaseNumber: Int?, content: String) async {
        // Create default phasing if it doesn't exist
        if !artifactManager.fileExists("phasing.md") {
            print("[Orchestrator] Creating default phasing.md first...")
            await writePhasing()
            // Small delay to ensure write completes
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if let phase = phaseNumber {
            lastResponse = "Editing phase \(phase)..."

            if artifactManager.editPhase(in: "phasing.md", phaseNumber: phase, newContent: content) {
                lastResponse = "Phase \(phase) updated"
            } else {
                lastResponse = "Failed to edit phase \(phase)"
            }
        } else {
            // Append to phasing if no specific phase
            if artifactManager.appendToFile(filename: "phasing.md", content: "\n\(content)") {
                lastResponse = "Phasing updated"
            } else {
                lastResponse = "Failed to edit phasing"
            }
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

            // Add assistant response to history
            addAssistantResponse(response)
        } catch {
            print("[Orchestrator] Failed to generate response: \(error)")
            lastResponse = "I couldn't process that. Try again?"
        }

        state = .idle
    }

    // MARK: - Context Management

    func addUserTranscript(_ transcript: String) {
        conversationHistory.append((role: "user", content: transcript))

        // Keep last 20 exchanges
        if conversationHistory.count > 40 {
            conversationHistory = Array(conversationHistory.suffix(40))
        }
    }

    func addAssistantResponse(_ response: String) {
        conversationHistory.append((role: "assistant", content: response))
    }
}