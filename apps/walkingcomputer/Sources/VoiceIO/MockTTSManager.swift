import Foundation

// MARK: - Mock TTS Manager for Testing

class MockTTSManager: TTSProtocol {
    var isSpeaking: Bool = false
    private var spokenTexts: [String] = []

    func speak(_ text: String, interruptible: Bool = true) async {
        print("    🔊 [Mock TTS] \(text)")
        spokenTexts.append(text)
        isSpeaking = true

        // Simulate brief speech delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        isSpeaking = false
    }

    func stop() {
        isSpeaking = false
        print("    🔇 [Mock TTS] Stopped")
    }

    // Testing helper
    func getSpokenTexts() -> [String] {
        return spokenTexts
    }

    func clearHistory() {
        spokenTexts.removeAll()
    }
}