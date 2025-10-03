import SwiftUI

struct SessionListView: View {
    @StateObject private var viewModel: SessionListViewModel
    @Environment(\.dismiss) private var dismiss

    init(sessionManager: SessionManager) {
        _viewModel = StateObject(wrappedValue: SessionListViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        NavigationView {
            listContent
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(
                    leading: Button("Close") {
                        dismiss()
                    },
                    trailing: Button(action: {
                        viewModel.createNewSession()
                        dismiss()
                    }) {
                        Image(systemName: "plus")
                    }
                )
        }
        .sheet(item: Binding(
            get: { viewModel.selectedFile.map { FileSelection(session: $0.session, node: $0.node) } },
            set: { newValue in
                if newValue == nil {
                    viewModel.clearFileSelection()
                }
            }
        )) { selection in
            ArtifactContentView(
                session: selection.session,
                fileNode: selection.node,
                sessionStore: viewModel.sessionManager.sessionStore
            )
        }
        .onAppear {
            viewModel.refreshSessions()
        }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.sessions, id: \.id) { session in
                SessionRowWithArtifacts(
                    session: session,
                    isActive: viewModel.isActiveSession(session),
                    isExpanded: viewModel.isExpanded(session),
                    relativeTime: viewModel.relativeTime(for: session.lastUpdated),
                    artifacts: viewModel.getArtifacts(for: session),
                    onSessionTap: {
                        viewModel.switchToSession(session)
                        dismiss()
                    },
                    onDisclosureTap: {
                        viewModel.toggleExpansion(for: session)
                    },
                    onFileTap: { node in
                        viewModel.selectFile(session: session, node: node)
                    }
                )
                .listRowBackground(Color(uiColor: .systemBackground))
                .listRowSeparator(.hidden)
                .id(session.id)
            }
        }
        .listStyle(.plain)
        .animation(.default, value: viewModel.sessions.map { $0.id })
    }
}

struct FileSelection: Identifiable {
    let id = UUID()
    let session: Session
    let node: ArtifactFileNode
}

struct SessionRowWithArtifacts: View {
    let session: Session
    let isActive: Bool
    let isExpanded: Bool
    let relativeTime: String
    let artifacts: [ArtifactFileNode]
    let onSessionTap: () -> Void
    let onDisclosureTap: () -> Void
    let onFileTap: (ArtifactFileNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session header
            HStack(spacing: 16) {
                Button(action: onDisclosureTap) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(PlainButtonStyle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(sessionIdPreview)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(isActive ? .blue : .primary)

                    Text(relativeTime)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 22))
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSessionTap)

            // Artifact tree (when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(artifacts) { node in
                        ArtifactNodeRow(node: node, indentLevel: 0, onFileTap: onFileTap)
                    }
                }
                .padding(.leading, 48)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
        }
    }

    private var sessionIdPreview: String {
        let uuid = session.id.uuidString
        return String(uuid.prefix(8))
    }
}

struct ArtifactNodeRow: View {
    let node: ArtifactFileNode
    let indentLevel: Int
    let onFileTap: (ArtifactFileNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                    .foregroundColor(node.isDirectory ? .blue : .secondary)
                    .font(.system(size: 15))
                    .frame(width: 22)

                Text(node.name)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(node.isDirectory ? .primary : .secondary)
            }
            .padding(.leading, CGFloat(indentLevel * 24))
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                if !node.isDirectory {
                    onFileTap(node)
                }
            }

            // Render children recursively
            if node.isDirectory {
                ForEach(node.children) { child in
                    ArtifactNodeRow(node: child, indentLevel: indentLevel + 1, onFileTap: onFileTap)
                }
            }
        }
    }
}
