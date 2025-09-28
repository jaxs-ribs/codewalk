import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()
    @State private var showCopiedFeedback = false
    @State private var copiedMessage = ""

    var body: some View {
        Color.white
            .ignoresSafeArea(.all)
            .overlay(
                VStack {
                    // Status indicator (top)
                    HStack {
                        Text("Walking Computer")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Copied feedback
                    if showCopiedFeedback {
                        Text(copiedMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                            .transition(.opacity)
                    }

                    // Main circle UI
                    CircleView(viewModel: viewModel)

                    // Clipboard buttons (below circle)
                    HStack(spacing: 20) {
                        Button(action: {
                            copyDescription()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                Text("Description")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 80, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }

                        Button(action: {
                            copyPhasing()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "list.bullet.clipboard")
                                    .font(.system(size: 24))
                                    .foregroundColor(.green)
                                Text("Phasing")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 80, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }

                        Button(action: {
                            copyBoth()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 24))
                                    .foregroundColor(.purple)
                                Text("Both")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 80, height: 60)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top, 20)

                    Spacer()
                    
                    // Last message (bottom)
                    Text(viewModel.lastMessage)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .lineLimit(2)
                }
            )
            .persistentSystemOverlays(.hidden)
            .statusBarHidden()
            .onAppear {
                UIApplication.shared.isStatusBarHidden = true
            }
    }

    // MARK: - Clipboard Actions

    private func copyDescription() {
        guard let orchestrator = viewModel.orchestrator else { return }

        if orchestrator.copyDescriptionToClipboard() {
            showFeedback("Description copied!")
        } else {
            showFeedback("No description to copy")
        }
    }

    private func copyPhasing() {
        guard let orchestrator = viewModel.orchestrator else { return }

        if orchestrator.copyPhasingToClipboard() {
            showFeedback("Phasing copied!")
        } else {
            showFeedback("No phasing to copy")
        }
    }

    private func copyBoth() {
        guard let orchestrator = viewModel.orchestrator else { return }

        if orchestrator.copyBothToClipboard() {
            showFeedback("Both artifacts copied!")
        } else {
            showFeedback("No artifacts to copy")
        }
    }

    private func showFeedback(_ message: String) {
        copiedMessage = message
        withAnimation(.easeInOut(duration: 0.3)) {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCopiedFeedback = false
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
