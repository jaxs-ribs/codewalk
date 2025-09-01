import Foundation

/// Loads configuration from .env file (bundled in app) or environment variables.
/// Required: GROQ_API_KEY, RELAY_WS_URL, RELAY_SESSION_ID, RELAY_TOKEN
struct EnvConfig {
  var groqApiKey: String = ""
  var relayWsUrl: String = ""
  var sessionId: String = ""
  var token: String = ""

  static func load() -> EnvConfig {
    // Try bundled .env first
    if let url = Bundle.main.url(forResource: ".env", withExtension: nil),
       let text = try? String(contentsOf: url, encoding: .utf8) {
      return parse(text: text)
    }
    // Try process environment (Debug)
    let env = ProcessInfo.processInfo.environment
    var c = EnvConfig()
    c.groqApiKey = env["GROQ_API_KEY"] ?? ""
    c.relayWsUrl = env["RELAY_WS_URL"] ?? ""
    c.sessionId = env["RELAY_SESSION_ID"] ?? ""
    c.token = env["RELAY_TOKEN"] ?? ""
    return c
  }

  static func parse(text: String) -> EnvConfig {
    var c = EnvConfig()
    text.split(separator: "\n").forEach { lineSub in
      let line = String(lineSub)
      guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
            let eq = line.firstIndex(of: "=") else { return }
      let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
      let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
      switch key {
      case "GROQ_API_KEY": c.groqApiKey = value
      case "RELAY_WS_URL": c.relayWsUrl = value
      case "RELAY_SESSION_ID": c.sessionId = value
      case "RELAY_TOKEN": c.token = value
      default: break
      }
    }
    return c
  }
}

