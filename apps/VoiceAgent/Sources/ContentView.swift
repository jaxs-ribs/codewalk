import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AgentViewModel()
    @State private var debugOpacity: Double = 0
    
    var body: some View {
        Color.white
            .ignoresSafeArea(.all)
            .overlay(
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    CircleView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                    
                    Spacer(minLength: 0)
                    
                    if viewModel.debugMode {
                        VStack(spacing: 16) {
                            Text(viewModel.currentState.rawValue)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.gray.opacity(0.6))
                                .opacity(debugOpacity)
                            
                            HStack(spacing: 10) {
                                ForEach(AgentState.allCases, id: \.self) { state in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            viewModel.transitionTo(state)
                                        }
                                    }) {
                                        Text(state.rawValue)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(
                                                        viewModel.currentState == state ?
                                                        Color.black :
                                                        Color.gray.opacity(0.1)
                                                    )
                                            )
                                            .foregroundColor(
                                                viewModel.currentState == state ?
                                                .white : .black.opacity(0.6)
                                            )
                                            .scaleEffect(viewModel.currentState == state ? 1.05 : 1.0)
                                    }
                                }
                            }
                            .opacity(debugOpacity)
                        }
                        .padding(.bottom, 50)
                    }
                }
            )
            .persistentSystemOverlays(.hidden)
            .statusBarHidden()
            .onAppear {
                UIApplication.shared.isStatusBarHidden = true
                withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                    debugOpacity = 1
                }
            }
    }
}

#Preview {
    ContentView()
}