import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Handles artifact-related actions: read, write, edit, split, merge
class ArtifactActionHandler: ActionHandler {
    private let artifactManager: ArtifactManager
    private let assistantClient: AssistantClient
    private let voiceOutput: VoiceOutputManager
    private let conversationContext: ConversationContext
    var lastResponse: String = ""

    init(
        artifactManager: ArtifactManager,
        assistantClient: AssistantClient,
        voiceOutput: VoiceOutputManager,
        conversationContext: ConversationContext
    ) {
        self.artifactManager = artifactManager
        self.assistantClient = assistantClient
        self.voiceOutput = voiceOutput
        self.conversationContext = conversationContext
    }

    func canHandle(_ action: ProposedAction) -> Bool {
        switch action {
        case .writeDescription, .writePhasing, .writeBoth,
             .readDescription, .readPhasing, .readSpecificPhase,
             .editDescription, .editPhasing,
             .splitPhase, .mergePhases,
             .copyDescription, .copyPhasing, .copyBoth:
            return true
        default:
            return false
        }
    }

    func handle(_ action: ProposedAction) async {
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
        case .splitPhase(let phaseNumber, let instructions):
            await splitPhase(phaseNumber, instructions: instructions)
        case .mergePhases(let startPhase, let endPhase, let instructions):
            await mergePhases(startPhase, endPhase: endPhase, instructions: instructions)
        case .copyDescription:
            await copyDescriptionAction()
        case .copyPhasing:
            await copyPhasingAction()
        case .copyBoth:
            await copyBothAction()
        default:
            break
        }
    }

    // MARK: - Write Operations

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

                // Auto-load artifact into context
                loadArtifactIntoContext(type: type, content: content)

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
                conversationHistory: conversationContext.allMessages()
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
                conversationHistory: conversationContext.allMessages(),
                statusCallback: statusCallbackToUse
            )
        }
    }

    private func addAssistantWriteConfirmation(for type: ArtifactType) {
        switch type {
        case .description:
            conversationContext.addAssistantMessage("I've written the project description based on our conversation.")
        case .phasing:
            conversationContext.addAssistantMessage("I've written the project phasing based on our conversation.")
        }
    }

    // MARK: - Read Operations

    private func readDescription() async {
        if let content = artifactManager.safeRead(filename: "description.md") {
            lastResponse = "Reading description..."
            log("Read description (\(content.count) chars)", category: .artifacts, component: "ArtifactActionHandler")

            await speak(content)
        } else {
            lastResponse = "No description yet."
            await speak(lastResponse)

            let files = artifactManager.listArtifacts()
            log("Current artifacts: \(files.joined(separator: ", "))", category: .artifacts, component: "ArtifactActionHandler")
        }
    }

    private func readPhasing() async {
        if let content = artifactManager.safeRead(filename: "phasing.md") {
            lastResponse = "Reading phasing..."
            log("Read phasing (\(content.count) chars)", category: .artifacts, component: "ArtifactActionHandler")

            await speak(content)
        } else {
            lastResponse = "No phasing yet."
            await speak(lastResponse)

            let files = artifactManager.listArtifacts()
            log("Current artifacts: \(files.joined(separator: ", "))", category: .artifacts, component: "ArtifactActionHandler")
        }
    }

    private func readSpecificPhase(_ phaseNumber: Int) async {
        if let phaseContent = artifactManager.readPhase(from: "phasing.md", phaseNumber: phaseNumber) {
            lastResponse = phaseContent
            log("Read phase \(phaseNumber) (\(phaseContent.count) chars)", category: .artifacts, component: "ArtifactActionHandler")

            await speak(phaseContent)
        } else {
            lastResponse = "Phase \(phaseNumber) not found."
            await speak(lastResponse)
        }
    }

    // MARK: - Edit Operations

    private func editDescription(content: String) async {
        await editArtifact(type: .description, content: content, phaseNumber: nil)
    }

    private func editPhasing(phaseNumber: Int?, content: String) async {
        await editArtifact(type: .phasing, content: content, phaseNumber: phaseNumber)
    }

    private func editArtifact(type: ArtifactType, content: String, phaseNumber: Int?) async {
        lastResponse = "Updating \(type.displayName)..."

        // If editing a specific phase number, use the diff-based approach
        if type == .phasing, let phase = phaseNumber {
            // Get config for groq API key
            guard let config = try? EnvConfig.load() else {
                lastResponse = "Failed to load configuration for phase editing"
                await speak(lastResponse)
                return
            }

            await speak("Editing phase \(phase)...")

            let success = await artifactManager.editSpecificPhase(phase, instructions: content, groqApiKey: config.groqApiKey)

            if success {
                lastResponse = "Phase \(phase) updated."
                await speak(lastResponse)
                conversationContext.addAssistantMessage("I've updated phase \(phase) based on your instructions: \(content)")

                // Auto-load updated phasing into context
                if let updatedContent = artifactManager.safeRead(filename: "phasing.md") {
                    loadArtifactIntoContext(type: .phasing, content: updatedContent)
                }
            } else {
                lastResponse = "Failed to update phase \(phase)"
                await speak(lastResponse)
            }
            return
        }

        // For full artifact edits, use the existing regeneration approach
        do {
            // Add the edit request to conversation history as a requirement
            if type == .phasing {
                conversationContext.addUserMessage("Additional requirement for the phasing: \(content)")
            } else {
                conversationContext.addUserMessage("Additional requirement for the \(type.displayName): \(content)")
            }

            // Regenerate the artifact with the new requirement included
            let updatedContent: String
            switch type {
            case .description:
                updatedContent = try await assistantClient.generateDescription(conversationHistory: conversationContext.allMessages())
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
                updatedContent = try await assistantClient.generatePhasing(conversationHistory: conversationContext.allMessages(), statusCallback: statusCallback)
            }

            // Save the regenerated artifact
            if artifactManager.safeWrite(filename: type.filename, content: updatedContent) {
                lastResponse = "\(type.displayName.capitalized) updated."
                await speak(lastResponse)
                conversationContext.addAssistantMessage("I've regenerated the \(type.displayName) with your new requirement.")

                // Auto-load updated artifact into context
                loadArtifactIntoContext(type: type, content: updatedContent)
            } else {
                lastResponse = "Failed to update \(type.displayName)"
                await speak(lastResponse)
            }
        } catch {
            logError("Failed to regenerate \(type.displayName): \(error)", component: "ArtifactActionHandler")
            lastResponse = "Failed to regenerate \(type.displayName)"
            await speak(lastResponse)
        }
    }

    // MARK: - Phase Operations

    private func splitPhase(_ phaseNumber: Int, instructions: String) async {
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
            conversationContext.addAssistantMessage("I've split phase \(phaseNumber) based on your instructions: \(instructions)")

            // Auto-load updated phasing into context
            if let updatedContent = artifactManager.safeRead(filename: "phasing.md") {
                loadArtifactIntoContext(type: .phasing, content: updatedContent)
            }
        } else {
            lastResponse = "Failed to split phase \(phaseNumber)"
            await speak(lastResponse)
        }
    }

    private func mergePhases(_ startPhase: Int, endPhase: Int, instructions: String?) async {
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
            conversationContext.addAssistantMessage("I've merged phases \(startPhase) through \(endPhase)")

            // Auto-load updated phasing into context
            if let updatedContent = artifactManager.safeRead(filename: "phasing.md") {
                loadArtifactIntoContext(type: .phasing, content: updatedContent)
            }
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

    // MARK: - Copy Operations

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

    private func copyDescriptionToClipboard() -> Bool {
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

    private func copyPhasingToClipboard() -> Bool {
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

    private func copyBothToClipboard() -> Bool {
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

    // MARK: - Helpers

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

    private func handleGenerationError(_ error: Error, for artifact: String) -> String {
        logError("Failed to generate \(artifact): \(error)", component: "ArtifactActionHandler")

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

    private func speak(_ text: String) async {
        await voiceOutput.speak(text)
    }

    /// Load artifact content into conversation context (silently, no TTS)
    private func loadArtifactIntoContext(type: ArtifactType, content: String) {
        conversationContext.addSilentContextMessage(content, type: "Updated \(type.filename)")
        log("Loaded \(type.filename) into context (\(content.count) chars)", category: .artifacts, component: "ArtifactActionHandler")
    }
}
