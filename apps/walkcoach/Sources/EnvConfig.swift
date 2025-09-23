import Foundation

/// Loads configuration from .env file or environment variables.
struct EnvConfig {
    var groqApiKey: String = ""

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

        print("[WalkCoach] Loaded config:")
        print("[WalkCoach] - GROQ_API_KEY: \(config.groqApiKey.prefix(10))...")

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
            default:
                break
            }
        }

        print("[WalkCoach] Parsed .env file")
        return config
    }
}