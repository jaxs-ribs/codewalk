import SwiftUI
import Combine

@MainActor
class AgentViewModel: ObservableObject {
    @Published var currentState: AgentState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var debugMode: Bool = true
    
    private var audioTimer: Timer?
    
    func handleCircleTap() {
        switch currentState {
        case .idle:
            transitionTo(.recording)
        case .recording:
            transitionTo(.idle)
        case .transcribing, .talking:
            transitionTo(.recording)
        }
    }
    
    func transitionTo(_ newState: AgentState) {
        let generator = UINotificationFeedbackGenerator()
        
        if newState == .recording {
            generator.notificationOccurred(.success)
        } else if currentState == .recording {
            generator.notificationOccurred(.warning)
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)) {
            currentState = newState
        }
        
        audioTimer?.invalidate()
        
        if newState == .talking {
            simulateAudioLevels()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                audioLevel = 0.0
            }
        }
    }
    
    private func simulateAudioLevels() {
        audioTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                let targetLevel = Float.random(in: 0.1...0.9)
                withAnimation(.easeInOut(duration: 0.1)) {
                    self.audioLevel = self.audioLevel * 0.7 + targetLevel * 0.3
                }
            }
        }
    }
}