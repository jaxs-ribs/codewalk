import Foundation

// ANSI color codes for beautiful terminal output
enum AnsiColor: String {
    // Main palette - soft, pleasant colors
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case italic = "\u{001B}[3m"

    // Primary colors
    case purple = "\u{001B}[38;5;141m"      // Soft purple for main app logs
    case cyan = "\u{001B}[38;5;80m"         // Bright cyan for network/API
    case green = "\u{001B}[38;5;120m"       // Soft green for success
    case yellow = "\u{001B}[38;5;221m"      // Warm yellow for processing
    case coral = "\u{001B}[38;5;209m"       // Coral for TTS/audio
    case blue = "\u{001B}[38;5;111m"        // Soft blue for system/init
    case pink = "\u{001B}[38;5;213m"        // Pink for user input/STT
    case orange = "\u{001B}[38;5;208m"      // Orange for router/orchestrator
    case red = "\u{001B}[38;5;204m"         // Soft red for errors
    case mint = "\u{001B}[38;5;121m"        // Mint green for artifacts
    case lavender = "\u{001B}[38;5;183m"    // Lavender for search

    // Background colors for emphasis
    case bgDark = "\u{001B}[48;5;236m"      // Dark background
    case bgLight = "\u{001B}[48;5;238m"     // Slightly lighter background
}

enum LogCategory {
    case app           // Main app logs (purple)
    case recorder      // Audio recording (coral)
    case stt           // Speech-to-text (pink)
    case tts           // Text-to-speech (coral)
    case router        // Routing logic (orange)
    case orchestrator  // Orchestration (orange)
    case assistant     // Assistant responses (cyan)
    case artifacts     // Artifact management (mint)
    case network       // Network operations (cyan)
    case search        // Search service (lavender)
    case system        // System/init messages (blue)
    case success       // Success messages (green)
    case error         // Error messages (red)
    case userInput     // User transcripts (pink + bold)
    case aiResponse    // AI spoken responses (cyan + bold)

    var color: AnsiColor {
        switch self {
        case .app: return .purple
        case .recorder: return .coral
        case .stt: return .pink
        case .tts: return .coral
        case .router: return .orange
        case .orchestrator: return .orange
        case .assistant: return .cyan
        case .artifacts: return .mint
        case .network: return .cyan
        case .search: return .lavender
        case .system: return .blue
        case .success: return .green
        case .error: return .red
        case .userInput: return .pink
        case .aiResponse: return .cyan
        }
    }

    var icon: String {
        switch self {
        case .app: return "🚀"
        case .recorder: return "🎙️"
        case .stt: return "🗣️"
        case .tts: return "🔊"
        case .router: return "🧭"
        case .orchestrator: return "🎯"
        case .assistant: return "🤖"
        case .artifacts: return "📝"
        case .network: return "🌐"
        case .search: return "🔍"
        case .system: return "⚙️"
        case .success: return "✅"
        case .error: return "❌"
        case .userInput: return "👤"
        case .aiResponse: return "💬"
        }
    }

    var label: String {
        switch self {
        case .app: return "WalkCoach"
        case .recorder: return "Recorder"
        case .stt: return "STT"
        case .tts: return "TTS"
        case .router: return "Router"
        case .orchestrator: return "Orchestrator"
        case .assistant: return "Assistant"
        case .artifacts: return "Artifacts"
        case .network: return "Network"
        case .search: return "Search"
        case .system: return "System"
        case .success: return "Success"
        case .error: return "Error"
        case .userInput: return "User"
        case .aiResponse: return "AI"
        }
    }
}

class Logger {
    static let shared = Logger()
    private let formatter = DateFormatter()
    private let logQueue = DispatchQueue(label: "com.walkingcomputer.logger", qos: .utility)

    private init() {
        formatter.dateFormat = "HH:mm:ss.SSS"
        printHeader()
    }

    private func printHeader() {
        print("\n\(AnsiColor.purple.rawValue)💻 Walking Computer v1.0\(AnsiColor.reset.rawValue)")
        print("\(AnsiColor.dim.rawValue)Started: \(Date())\(AnsiColor.reset.rawValue)")
        print("\(AnsiColor.dim.rawValue)Press Ctrl+C to stop\(AnsiColor.reset.rawValue)\n")
    }

    func log(_ message: String, category: LogCategory = .app, component: String? = nil) {
        let timestamp = formatter.string(from: Date())
        let label = component ?? category.label
        let color = category.color.rawValue
        let icon = category.icon

        // Simple, clean format with color and full info
        let formattedMessage = "\(AnsiColor.dim.rawValue)[\(timestamp)]\(AnsiColor.reset.rawValue) \(color)\(icon) \(label):\(AnsiColor.reset.rawValue) \(color)\(message)\(AnsiColor.reset.rawValue)"

        print(formattedMessage)
    }


    // Convenience methods for common log types
    func userTranscript(_ text: String) {
        log(text, category: .userInput)
    }

    func aiSpokenResponse(_ text: String) {
        log(text, category: .aiResponse)
    }

    func success(_ message: String, component: String? = nil) {
        log(message, category: .success, component: component)
    }

    func error(_ message: String, component: String? = nil) {
        log(message, category: .error, component: component)
    }

    func network(_ message: String, component: String? = nil) {
        log(message, category: .network, component: component ?? "Network")
    }


}

// Global convenience functions
func log(_ message: String, category: LogCategory = .app, component: String? = nil) {
    Logger.shared.log(message, category: category, component: component)
}

func logUserTranscript(_ text: String) {
    Logger.shared.userTranscript(text)
}

func logAIResponse(_ text: String) {
    Logger.shared.aiSpokenResponse(text)
}

func logSuccess(_ message: String, component: String? = nil) {
    Logger.shared.success(message, component: component)
}

func logError(_ message: String, component: String? = nil) {
    Logger.shared.error(message, component: component)
}