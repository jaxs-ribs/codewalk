import Foundation

enum AgentState: String, CaseIterable {
    case idle = "Idle"
    case recording = "Recording"
    case transcribing = "Transcribing"
    case talking = "Talking"
    
    var breathingSpeed: Double {
        switch self {
        case .idle:
            return 2.5  // Base speed
        case .recording:
            return 1.5  // 40% faster than idle (2.5 / 1.66 ≈ 1.5)
        case .transcribing:
            return 1.5  // Same as recording
        case .talking:
            return 2.0  // Slightly faster than idle
        }
    }
}