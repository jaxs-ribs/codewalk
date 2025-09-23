import Foundation

/// Loads configuration from .env file or environment variables.
struct EnvConfig {
    var groqApiKey: String = ""
    var elevenLabsKey: String = ""
    var relayWsUrl: String = ""
    var sessionId: String = ""
    var token: String = ""
    
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
        config.elevenLabsKey = env["ELEVENLABS_KEY"] ?? ""
        config.relayWsUrl = env["RELAY_WS_URL"] ?? "ws://localhost:8080"
        config.sessionId = env["RELAY_SESSION_ID"] ?? ""
        config.token = env["RELAY_TOKEN"] ?? ""
        
        print("[EnvConfig] Loaded config:")
        print("[EnvConfig] - GROQ_API_KEY: \(config.groqApiKey.prefix(10))...")
        print("[EnvConfig] - ELEVENLABS_KEY: \(config.elevenLabsKey.prefix(10))...")
        print("[EnvConfig] - RELAY_WS_URL: \(config.relayWsUrl)")
        print("[EnvConfig] - RELAY_SESSION_ID: \(config.sessionId)")
        print("[EnvConfig] - RELAY_TOKEN: \(config.token.prefix(10))...")
        
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
            case "ELEVENLABS_KEY", "ELEVENLABS_API_KEY": 
                config.elevenLabsKey = value
            case "RELAY_WS_URL", "RELAY_URL": 
                config.relayWsUrl = value
            case "RELAY_SESSION_ID":
                config.sessionId = value
            case "RELAY_TOKEN":
                config.token = value
            default: 
                break
            }
        }
        
        print("[EnvConfig] Parsed .env file")
        return config
    }
}