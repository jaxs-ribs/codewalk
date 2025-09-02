import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()
    
    var body: some View {
        Color.white
            .ignoresSafeArea(.all)
            .overlay(
                CircleView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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