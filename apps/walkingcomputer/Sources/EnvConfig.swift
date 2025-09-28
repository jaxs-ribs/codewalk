import Foundation

/// Loads configuration from .env file or environment variables.
struct EnvConfig {
    var groqApiKey: String = ""
    var braveApiKey: String = ""
    var elevenLabsApiKey: String = ""
    var searchResultCount: Int = 8
    var fetchTimeoutMs: Int = 15000
    var searchModelId: String = "llama-3.1-70b-versatile"  // Using a working Groq model

    static func load() -> EnvConfig {
        // Try bundled .env first
        if let url = Bundle.main.url(forResource: ".env", withExtension: nil),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return parse(text: text)
        }

        // Try process environment (for development)
        let env = ProcessInfo.processInfo.environment
        var config = EnvConfig()
        config.groqApiKey = env["GROQ_API_KEY"] ?? ""
        config.braveApiKey = env["BRAVE_API_KEY"] ?? ""
        config.elevenLabsApiKey = env["ELEVENLABS_API_KEY"] ?? ""
        config.searchResultCount = Int(env["RESULT_COUNT"] ?? "8") ?? 8
        config.fetchTimeoutMs = Int(env["FETCH_TIMEOUT_MS"] ?? "15000") ?? 15000
        config.searchModelId = env["MODEL_ID"] ?? "llama-3.1-70b-versatile"

        print("[WalkCoach] Loaded config:")
        print("[WalkCoach] - GROQ_API_KEY: \(config.groqApiKey.prefix(10))...")
        print("[WalkCoach] - BRAVE_API_KEY: \(config.braveApiKey.prefix(10))...")
        print("[WalkCoach] - ELEVENLABS_API_KEY: \(config.elevenLabsApiKey.prefix(10))...")
        print("[WalkCoach] - Search settings: \(config.searchResultCount) results, \(config.fetchTimeoutMs)ms timeout, model: \(config.searchModelId)")

        return config
    }

    static func parse(text: String) -> EnvConfig {
        var config = EnvConfig()

        text.split(separator: "\n").forEach { lineSub in
            let line = String(lineSub).trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let eq = line.firstIndex(of: "=") else { return }

            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "GROQ_API_KEY":
                config.groqApiKey = value
            case "BRAVE_API_KEY":
                config.braveApiKey = value
            case "ELEVENLABS_API_KEY":
                config.elevenLabsApiKey = value
            case "RESULT_COUNT":
                config.searchResultCount = Int(value) ?? 8
            case "FETCH_TIMEOUT_MS":
                config.fetchTimeoutMs = Int(value) ?? 15000
            case "MODEL_ID":
                config.searchModelId = value
            default:
                break
            }
        }

        print("[WalkCoach] Parsed .env file")
        return config
    }
}