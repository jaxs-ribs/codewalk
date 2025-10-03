import SwiftUI

struct SessionListView: View {
    @StateObject private var viewModel: SessionListViewModel
    @Environment(\.dismiss) private var dismiss

    init(sessionManager: SessionManager) {
        _viewModel = StateObject(wrappedValue: SessionListViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.sessions) { session in
                    SessionRow(
                        session: session,
                        isActive: viewModel.isActiveSession(session),
                        relativeTime: viewModel.relativeTime(for: session.lastUpdated)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.switchToSession(session)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.createNewSession()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            viewModel.refreshSessions()
        }
    }
}

struct SessionRow: View {
    let session: Session
    let isActive: Bool
    let relativeTime: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionIdPreview)
                    .font(.body)
                    .foregroundColor(isActive ? .blue : .primary)

                Text("Last updated: \(relativeTime)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private var sessionIdPreview: String {
        let uuid = session.id.uuidString
        return String(uuid.prefix(8))
    }
}
