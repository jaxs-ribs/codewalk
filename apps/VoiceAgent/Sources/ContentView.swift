import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()
    
    var body: some View {
        Color.white
            .ignoresSafeArea(.all)
            .overlay(
                VStack {
                    // Connection status indicator (top)
                    HStack {
                        Circle()
                            .fill(viewModel.connectionStatus == "Open" ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding()
                    
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
            .persistentSystemOverlays(.hidden)
            .statusBarHidden()
            .onAppear {
                UIApplication.shared.isStatusBarHidden = true
            }
    }
}

#Preview {
    ContentView()
}