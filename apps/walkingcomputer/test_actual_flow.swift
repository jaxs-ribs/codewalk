// Actual flow:

var conversationHistory: [(role: String, content: String)] = []

// User asks question
conversationHistory.append((role: "user", content: "How many phases?"))

// Context gets injected (line 828 in Orchestrator)
conversationHistory.append((role: "system", content: "IMPORTANT: artifact content here"))

// Then generateConversationalResponse is called with this history

// Inside generateConversationalResponse (line 279-283):
let lastUserMessage = conversationHistory.last { $0.role == "user" }?.content ?? ""
print("lastUserMessage: \(lastUserMessage)")

let historyWithoutLast = Array(conversationHistory.dropLast())
print("\nhistoryWithoutLast:")
for msg in historyWithoutLast {
    print("  \(msg.role): \(msg.content)")
}

// Then buildMessages creates:
print("\n=== Final messages to LLM ===")
print("1. system: [Voice-first project speccer...]")
for (i, msg) in historyWithoutLast.enumerated() {
    print("\(i+2). \(msg.role): \(msg.content)")
}
print("\(historyWithoutLast.count + 2). user: \(lastUserMessage)")
