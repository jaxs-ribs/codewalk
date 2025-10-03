import SwiftUI

struct ArtifactContentView: View {
    let session: Session
    let fileNode: ArtifactFileNode
    let sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)

                        Text("Error")
                            .font(.headline)

                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(fileNode.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            loadContent()
        }
    }

    private func loadContent() {
        let baseURL = sessionStore.getBaseURL()

        // Handle conversation.json specially (it's at session root, not in artifacts)
        let filePath: URL
        if fileNode.name == "conversation.json" {
            filePath = session.conversationPath(in: baseURL)
        } else {
            let artifactsPath = session.artifactsPath(in: baseURL)
            filePath = artifactsPath.appendingPathComponent(fileNode.relativePath)
        }

        do {
            content = try String(contentsOf: filePath, encoding: .utf8)
            isLoading = false
            log("Loaded content for \(fileNode.name)", category: .system, component: "ArtifactContentView")
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            isLoading = false
            logError("Failed to load content for \(fileNode.name): \(error)", component: "ArtifactContentView")
        }
    }
}
