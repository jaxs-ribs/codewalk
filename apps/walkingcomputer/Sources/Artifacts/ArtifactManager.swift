import Foundation

// MARK: - Artifact Manager (Facade)

/// Facade that delegates to ArtifactStore and PhaseEditor
class ArtifactManager {
    private let store: ArtifactStore
    private let phaseEditor: PhaseEditor

    init(groqApiKey: String, sessionId: UUID? = nil) {
        store = ArtifactStore(sessionId: sessionId)
        phaseEditor = PhaseEditor(store: store, groqApiKey: groqApiKey)

        if let sessionId = sessionId {
            log("Initialized for session: \(sessionId)", category: .artifacts, component: "ArtifactManager")
        } else {
            log("Initialized in legacy mode", category: .artifacts, component: "ArtifactManager")
        }
    }

    // Legacy constructor for compatibility
    convenience init() {
        let config = (try? EnvConfig.load()) ?? EnvConfig.load()
        self.init(groqApiKey: config.groqApiKey, sessionId: nil)
    }

    // MARK: - Delegated to ArtifactStore

    func safeRead(filename: String) -> String? {
        return store.read(filename: filename)
    }

    func safeWrite(filename: String, content: String) -> Bool {
        return store.write(filename: filename, content: content)
    }

    func listArtifacts() -> [String] {
        return store.listArtifacts()
    }

    func fileExists(_ filename: String) -> Bool {
        return store.fileExists(filename)
    }

    func getFullPath(for filename: String) -> URL {
        return store.getFullPath(for: filename)
    }

    // MARK: - Delegated to PhaseEditor

    func readPhase(from filename: String, phaseNumber: Int) -> String? {
        return phaseEditor.readPhase(from: filename, phaseNumber: phaseNumber)
    }

    func splitPhase(_ phaseNumber: Int, instructions: String, groqApiKey: String) async -> Bool {
        return await phaseEditor.splitPhase(phaseNumber, instructions: instructions)
    }

    func mergePhases(_ startPhase: Int, _ endPhase: Int, instructions: String?, groqApiKey: String) async -> Bool {
        return await phaseEditor.mergePhases(startPhase, endPhase, instructions: instructions)
    }

    func editSpecificPhase(_ phaseNumber: Int, instructions: String, groqApiKey: String) async -> Bool {
        return await phaseEditor.editPhase(phaseNumber, instructions: instructions)
    }
}
