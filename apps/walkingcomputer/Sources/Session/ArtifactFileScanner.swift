import Foundation

/// Represents a file node in the artifact tree
struct ArtifactFileNode: Identifiable, Equatable {
    let id: UUID = UUID()
    let name: String
    let relativePath: String
    let isDirectory: Bool
    var children: [ArtifactFileNode]

    static func == (lhs: ArtifactFileNode, rhs: ArtifactFileNode) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Scans session artifacts directory and builds file tree
class ArtifactFileScanner {
    private let fileManager = FileManager.default

    /// Scans artifacts directory for a session and returns file tree
    func scanArtifacts(for session: Session, baseURL: URL) -> [ArtifactFileNode] {
        let sessionPath = session.sessionPath(in: baseURL)
        let artifactsPath = session.artifactsPath(in: baseURL)

        var nodes: [ArtifactFileNode] = []

        // Add conversation.json if it exists
        let conversationPath = session.conversationPath(in: baseURL)
        if fileManager.fileExists(atPath: conversationPath.path) {
            nodes.append(ArtifactFileNode(
                name: "conversation.json",
                relativePath: "conversation.json",
                isDirectory: false,
                children: []
            ))
        }

        guard fileManager.fileExists(atPath: artifactsPath.path) else {
            log("No artifacts directory for session: \(session.id)", category: .system, component: "ArtifactFileScanner")
            return nodes
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: artifactsPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                // Skip backups directory
                if url.lastPathComponent == "backups" {
                    continue
                }

                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false
                let relativePath = url.lastPathComponent

                if isDirectory {
                    // Recursively scan subdirectory
                    let children = scanDirectory(at: url, relativeTo: artifactsPath)
                    nodes.append(ArtifactFileNode(
                        name: url.lastPathComponent,
                        relativePath: relativePath,
                        isDirectory: true,
                        children: children
                    ))
                } else {
                    nodes.append(ArtifactFileNode(
                        name: url.lastPathComponent,
                        relativePath: relativePath,
                        isDirectory: false,
                        children: []
                    ))
                }
            }

            log("Scanned \(nodes.count) artifacts for session: \(session.id)", category: .system, component: "ArtifactFileScanner")
            return nodes
        } catch {
            logError("Failed to scan artifacts: \(error)", component: "ArtifactFileScanner")
            return []
        }
    }

    private func scanDirectory(at url: URL, relativeTo baseURL: URL) -> [ArtifactFileNode] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var nodes: [ArtifactFileNode] = []

            for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false
                let relativePath = itemURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")

                if isDirectory {
                    let children = scanDirectory(at: itemURL, relativeTo: baseURL)
                    nodes.append(ArtifactFileNode(
                        name: itemURL.lastPathComponent,
                        relativePath: relativePath,
                        isDirectory: true,
                        children: children
                    ))
                } else {
                    nodes.append(ArtifactFileNode(
                        name: itemURL.lastPathComponent,
                        relativePath: relativePath,
                        isDirectory: false,
                        children: []
                    ))
                }
            }

            return nodes
        } catch {
            logError("Failed to scan directory \(url.path): \(error)", component: "ArtifactFileScanner")
            return []
        }
    }
}
