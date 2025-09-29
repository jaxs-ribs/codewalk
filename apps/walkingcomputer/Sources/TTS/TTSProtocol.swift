import Foundation

/// Protocol for TTS implementations (iOS native, mock for testing, etc.)
protocol TTSProtocol {
    /// Speak the given text asynchronously
    func speak(_ text: String, interruptible: Bool) async

    /// Stop current speech
    func stop()

    /// Whether TTS is currently speaking
    var isSpeaking: Bool { get }
}