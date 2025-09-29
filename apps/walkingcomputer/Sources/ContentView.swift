import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()

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
