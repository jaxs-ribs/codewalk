import Foundation

// MARK: - Artifact

struct Artifact: Codable, Equatable {
    let path: String
    let type: ArtifactType
    let keywords: [String]
    let topics: [String]
    let created: Date
    let summary: String

    enum ArtifactType: String, Codable {
        case spoken = "spoken"
        case context = "context"
    }
}

// MARK: - Registry Container

struct ArtifactRegistryData: Codable {
    var artifacts: [Artifact]
}

// MARK: - Artifact Registry

class ArtifactRegistry {
    private var data: ArtifactRegistryData
    private let registryURL: URL
    private let fileManager = FileManager.default

    init(artifactsPath: URL) {
        self.registryURL = artifactsPath.appendingPathComponent(".registry.json")

        // Try to load existing registry
        if let loadedData = ArtifactRegistry.loadFromDisk(url: registryURL) {
            self.data = loadedData
            log("Loaded registry with \(loadedData.artifacts.count) artifacts", category: .artifacts, component: "ArtifactRegistry")
        } else {
            // Create empty registry
            self.data = ArtifactRegistryData(artifacts: [])
            log("Created new empty registry", category: .artifacts, component: "ArtifactRegistry")
        }
    }

    // MARK: - Persistence

    func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: registryURL, options: .atomic)
            log("Saved registry with \(data.artifacts.count) artifacts", category: .artifacts, component: "ArtifactRegistry")
            return true
        } catch {
            logError("Failed to save registry: \(error)", component: "ArtifactRegistry")
            return false
        }
    }

    private static func loadFromDisk(url: URL) -> ArtifactRegistryData? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: url)
            let registry = try decoder.decode(ArtifactRegistryData.self, from: data)
            return registry
        } catch {
            logError("Failed to load registry: \(error)", component: "ArtifactRegistry")
            return nil
        }
    }

    func reload() {
        if let loadedData = ArtifactRegistry.loadFromDisk(url: registryURL) {
            self.data = loadedData
            log("Reloaded registry with \(loadedData.artifacts.count) artifacts", category: .artifacts, component: "ArtifactRegistry")
        }
    }

    // MARK: - Artifact Management

    func add(_ artifact: Artifact) {
        // Remove existing artifact with same path if present
        data.artifacts.removeAll { $0.path == artifact.path }
        data.artifacts.append(artifact)
        log("Added artifact: \(artifact.path)", category: .artifacts, component: "ArtifactRegistry")
    }

    func remove(path: String) {
        data.artifacts.removeAll { $0.path == path }
        log("Removed artifact: \(path)", category: .artifacts, component: "ArtifactRegistry")
    }

    func get(path: String) -> Artifact? {
        return data.artifacts.first { $0.path == path }
    }

    func all() -> [Artifact] {
        return data.artifacts
    }

    func count() -> Int {
        return data.artifacts.count
    }

    // MARK: - Fuzzy Matching

    func match(input: String, threshold: Double = 5.0) -> [Artifact] {
        let tokens = tokenize(input)

        let scored = data.artifacts.map { artifact in
            let score = fuzzyScore(tokens: tokens, artifact: artifact)
            return (artifact, score)
        }

        return scored
            .filter { $0.1 >= threshold }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func tokenize(_ input: String) -> [String] {
        // Common stop words to filter out
        let stopWords = Set(["a", "an", "the", "is", "are", "was", "were", "in", "on", "at", "to", "for", "of", "with", "about"])

        return input
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private func fuzzyScore(tokens: [String], artifact: Artifact) -> Double {
        var score = 0.0

        for token in tokens {
            // Exact keyword match = high score
            if artifact.keywords.contains(token) {
                score += 10.0
            }
            // Partial keyword match
            else if artifact.keywords.contains(where: { $0.contains(token) || token.contains($0) }) {
                score += 5.0
            }

            // Topic match
            if artifact.topics.contains(token) {
                score += 5.0
            }
            // Partial topic match
            else if artifact.topics.contains(where: { $0.contains(token) || token.contains($0) }) {
                score += 2.5
            }

            // Substring match in summary
            if artifact.summary.lowercased().contains(token) {
                score += 1.0
            }

            // Path match
            if artifact.path.lowercased().contains(token) {
                score += 3.0
            }
        }

        return score
    }
}
