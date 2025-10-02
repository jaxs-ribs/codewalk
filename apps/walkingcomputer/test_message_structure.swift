// Simulating the message structure

var conversationHistory: [(role: String, content: String)] = []

// User asks question
conversationHistory.append((role: "user", content: "How many phases are in the phasing?"))

// Context gets injected
conversationHistory.append((role: "system", content: "IMPORTANT: Use the following artifact content...\n[Context from artifacts/phasing.md]:\n# Project Phasing\n..."))

// Then buildMessages is called:
let systemPrompt = "Voice-first project speccer..."
let lastUserMessage = conversationHistory.last { $0.role == "user" }?.content ?? ""
let historyWithoutLast = Array(conversationHistory.dropLast())

print("=== What buildMessages sees ===")
print("systemPrompt (goes FIRST): \(systemPrompt.prefix(50))...")
print("\nhistory (goes MIDDLE):")
for msg in historyWithoutLast {
    print("  \(msg.role): \(msg.content.prefix(50))...")
}
print("\nlastUserMessage (goes LAST): \(lastUserMessage)")

print("\n=== Final message array sent to LLM ===")
print("1. system: \(systemPrompt.prefix(50))...")
for (i, msg) in historyWithoutLast.enumerated() {
    print("\(i+2). \(msg.role): \(msg.content.prefix(50))...")
}
print("\(historyWithoutLast.count + 2). user: \(lastUserMessage)")
