import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()
    @State private var showingSessionList = false

    var body: some View {
        Color.white
            .ignoresSafeArea(.all)
            .overlay(
                VStack {
                    Spacer()

                    // Main circle UI
                    CircleView(viewModel: viewModel)

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
            .overlay(
                // Session list button (top-right)
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showingSessionList = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundColor(.gray)
                                .padding()
                        }
                    }
                    Spacer()
                }
            )
            .sheet(isPresented: $showingSessionList) {
                if let sessionManager = viewModel.sessionManager {
                    SessionListView(sessionManager: sessionManager)
                }
            }
            .persistentSystemOverlays(.hidden)
            .statusBarHidden()
            .onAppear {
                UIApplication.shared.isStatusBarHidden = true
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
