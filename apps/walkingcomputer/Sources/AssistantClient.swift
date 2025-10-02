import Foundation

// MARK: - Assistant Client

class AssistantClient {
    private let groqApiKey: String
    private let modelName: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"

    // Constants
    private let maxTokens = 2000
    private let temperature = 0.7
    private let conversationHistoryLimit = 100

    init(groqApiKey: String, modelName: String) {
        self.groqApiKey = groqApiKey
        self.modelName = modelName
        // print("[AssistantClient] Initialized")
    }

    // MARK: - Content Generation

    func generateDescription(conversationHistory: [(role: String, content: String)]) async throws -> String {
        log("Generating description from conversation context", category: .assistant, component: "AssistantClient")

        let systemPrompt = """
        Generate a project description from this conversation.

        CRITICAL: Generate the actual markdown document, NOT a conversational response.

        CONTEXT:
        - Review the ENTIRE conversation history
        - Synthesize features the user WANTS
        - Silently omit anything user rejected
        - This is THE specification document

        TTS OPTIMIZATION:
        - Write conversationally, like explaining to a friend
        - Use contractions (it's, we'll, don't)
        - Short, clear sentences
        - No bullets, flowing prose only
        - Natural transitions ("so", "basically")

        CONTENT:
        - Comprehensive but concise (1200-1800 characters)
        - Only describe what WILL be built
        - Never mention what won't be included
        - Be thorough but direct

        Format:
        # Project Description

        [Your natural, speakable description]
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Generate the complete description markdown document based on our conversation. Start with '# Project Description' and include all details discussed.")

        return try await callGroq(messages: messages)
    }

    func generatePhasing(conversationHistory: [(role: String, content: String)], statusCallback: ((String) -> Void)? = nil) async throws -> String {
        log("Starting multi-pass phasing generation", category: .assistant, component: "AssistantClient")

        // Pass 1: Generate initial draft (Orchestrator already said "Writing phasing...")
        let draft = try await generatePhasingDraft(conversationHistory: conversationHistory)
        log("Pass 1 complete: generated \(draft.count) chars", category: .assistant, component: "AssistantClient")

        // Pass 2: Critique and redraft
        statusCallback?("Reviewing...")
        let refined = try await critiquePhasingDraft(draft: draft, conversationHistory: conversationHistory)
        log("Pass 2 complete: refined to \(refined.count) chars", category: .assistant, component: "AssistantClient")

        return refined
    }

    private func generatePhasingDraft(conversationHistory: [(role: String, content: String)]) async throws -> String {
        log("Pass 1: Generating phasing draft", category: .assistant, component: "AssistantClient")

        let systemPrompt = """
        Generate a project phasing plan from this conversation.

        CRITICAL: Generate the actual markdown document, NOT a conversational response.

        CONTEXT:
        - Extract features user WANTS from conversation
        - Silently exclude rejected features
        - Group into logical phases
        - This is THE implementation roadmap for Claude Code

        PHASE SIZING (CRITICAL):
        - Each phase = ONE focused unit of work completable in one session
        - A phase should build ONE capability or component, not multiple
        - If a phase needs to "set up X, then build Y, then add Z", split it into 3 phases
        - Good: "Add authentication endpoints", Bad: "Add authentication endpoints, build UI, connect database"
        - Phases build on each other incrementally
        - Aim for 5-8 phases total, not 3 mega-phases

        DEFINITION OF DONE - THE MOST CRITICAL PART:
        - DoD tests ONLY what THIS phase built, not the whole app
        - DoD verifies the MINIMUM that proves this phase is complete
        - Bad: testing the end-user experience before the feature is done
        - Good: testing the specific mechanism this phase introduced

        MENTAL MODEL:
        Phase: "Add database schema"
        BAD DoD: "User can log in and see their profile" (tests too much)
        GOOD DoD: "Run migrations, check schema with 'psql \\d users', see columns: id, email, created_at"

        Phase: "Create login API endpoint"
        BAD DoD: "User can log in from UI" (assumes UI exists)
        GOOD DoD: "Run curl -X POST /api/login with test user, receive 200 + JWT token"

        Phase: "Build login form component"
        BAD DoD: "Authentication works end-to-end" (assumes backend)
        GOOD DoD: "Click login button with test@example.com, form submits and console logs form data"

        Phase: "Implement touch detection"
        BAD DoD: "Swipe gesture works smoothly" (assumes gesture system)
        GOOD DoD: "Touch screen, see console log with touch coordinates and force value"

        FORMAT FOR DoD:
        - Start with action: "Run [command]", "Execute [script]", "Touch [element]", "Open [file]"
        - State expected output: "see [specific result]", "receive [specific response]", "prints [specific text]"
        - Be concrete: exact commands, exact expected values

        TTS OPTIMIZATION:
        - Each phase: one flowing paragraph
        - Use transitions: "So first", "Then", "After that"
        - Contractions always (we'll, it'll)
        - Natural, conversational tone

        CONTENT:
        - 5-8 phases covering accepted features only
        - Short titles (3-5 words)
        - Each phase: concise paragraph (150-250 chars)
        - Include specific technical details
        - Each phase builds ONE thing

        Format:
        # Project Phasing

        ## Phase 1: [Short Title]
        [Flowing paragraph describing the ONE thing this phase builds]
        **Definition of Done:** [Test that verifies ONLY this phase's work]

        ## Phase 2: [Short Title]
        [Flowing paragraph describing the ONE thing this phase builds]
        **Definition of Done:** [Test that verifies ONLY this phase's work]
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: conversationHistory,
                                    userPrompt: "Generate the complete phasing plan markdown document based on our conversation. Start with '# Project Phasing' and include all phases.")

        return try await callGroq(messages: messages)
    }

    private func critiquePhasingDraft(draft: String, conversationHistory: [(role: String, content: String)]) async throws -> String {
        log("Pass 2: Critiquing and refining phasing draft", category: .assistant, component: "AssistantClient")

        let systemPrompt = """
        You are reviewing a phasing plan draft. Check each phase against these criteria and output a CORRECTED version.

        CRITICAL CHECKS:

        1. PHASE GRANULARITY:
        - Does each phase build exactly ONE thing?
        - If a phase description says "set up X, then build Y, then add Z", split it into 3 separate phases
        - Count action verbs in the description - if >2, too big
        - Are there 5-8 phases total? If only 3-4, they're probably too broad

        2. DEFINITION OF DONE - SCOPE CHECK (MOST IMPORTANT):
        - Does the DoD test ONLY what this specific phase built?
        - RED FLAG: DoD tests end-user workflow before all pieces exist
        - RED FLAG: DoD assumes components from future phases
        - RED FLAG: DoD tests "the feature works" instead of "this piece works"

        EXAMPLES OF SCOPE VIOLATIONS TO FIX:

        Phase: "Add database schema"
        BAD DoD: "User can register and log in" ← NO! UI doesn't exist yet
        GOOD DoD: "Run 'psql \\d users', see columns: id, email, password_hash, created_at"

        Phase: "Create API endpoint"
        BAD DoD: "Click button, user sees success message" ← NO! Assumes UI
        GOOD DoD: "Run 'curl -X POST /api/users' with JSON, receive 201 + user ID"

        Phase: "Build UI form"
        BAD DoD: "Submit form, data saves to database" ← NO! Assumes backend integration
        GOOD DoD: "Click submit, console logs form data object with email and password fields"

        Phase: "Set up project"
        BAD DoD: "Run app, see 5 cards with swipe animation" ← NO! That's the final app
        GOOD DoD: "Run 'npm start', app compiles and shows blank screen at localhost:3000"

        3. DEFINITION OF DONE - FORMAT:
        - Must start with action: "Run...", "Execute...", "Touch...", "Open...", "Click..."
        - Must specify exact command or exact interaction
        - Must specify exact expected output

        4. GRANULARITY CHECK:
        - If a phase description mentions "then" more than once, split it
        - If a phase description has 3+ distinct tasks, split it

        5. DEPENDENCY CHECK:
        - Does phase N test features built in phase N+1? (time travel error)
        - Phases should be strictly sequential - later phases build on earlier ones

        INSTRUCTIONS:
        - Carefully review each phase's DoD against the scope rules
        - Split phases that are too large
        - Rewrite DoDs that test too broadly
        - Output corrected phasing plan in full, starting with "# Project Phasing"
        - Aim for 5-8 granular phases, not 3 mega-phases

        The goal: each phase should be ONE clear unit of work with a test that proves ONLY that unit is done.
        """

        let conversationContext = conversationHistory.suffix(20).map { exchange -> String in
            "\(exchange.role): \(exchange.content)"
        }.joined(separator: "\n")

        let userPrompt = """
        Review this phasing plan draft and output a corrected version:

        CONVERSATION CONTEXT (for reference):
        \(conversationContext)

        DRAFT TO REVIEW:
        \(draft)
        """

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: [],
                                    userPrompt: userPrompt)

        return try await callGroq(messages: messages)
    }

    func generateConversationalResponse(conversationHistory: [(role: String, content: String)], contextPrefix: String? = nil) async throws -> String {
        log("Generating conversational response", category: .assistant, component: "AssistantClient")

        // Build system prompt with optional context prefix
        var systemPrompt = ""

        if let context = contextPrefix {
            systemPrompt += context
        }

        systemPrompt += """
        Voice-first project speccer. Your responses will be spoken via TTS to someone walking.

        CORE RULES:
        1. Simple statements/ideas → Single word acknowledgment ("Noted", "Got it", "Sure")
        2. Questions → If artifact context is provided above, answer ONLY from that context. Count carefully and be precise. Otherwise, answer from your knowledge.
        3. Never suggest searching or mention search capability
        4. Never ask clarifying questions unless incomprehensible

        TTS OPTIMIZATION (for complex answers):
        - Focus on ONE key idea per response. Rarely two if essential.
        - One concept per sentence, keep sentences under 20 words
        - Connect sentences naturally with transitions, never enumerate
        - Avoid listing multiple items with colons or rapid-fire structure
        - Pick the most important point, not everything you know

        EXAMPLES:

        Simple exchanges (keep terse):
        "I want login" → "Noted"
        "Add dark mode" → "Got it"
        "What's the weather?" → "I don't have weather data"

        Complex information (structure for listening):
        "What's async await?" → "Async await lets you write asynchronous code that reads like regular code. Instead of callbacks, you just await the result."

        "Who invented computers?" → "Charles Babbage designed the first mechanical computer in the 1830s. Modern electronic computers came from Turing and von Neumann in the 1940s."

        THE KEY: One idea, clearly stated. Resist the urge to list multiple points. If they ask for more, they'll ask again.

        Default to brevity. Expand only when explaining something.
        """

        // Use the last user message as the prompt
        let lastUserMessage = conversationHistory.last { $0.role == "user" }?.content ?? ""

        let messages = buildMessages(systemPrompt: systemPrompt,
                                    conversationHistory: Array(conversationHistory.dropLast()),
                                    userPrompt: lastUserMessage)

        return try await callGroq(messages: messages)
    }

    // MARK: - Helper Methods

    private func buildMessages(systemPrompt: String,
                              conversationHistory: [(role: String, content: String)],
                              userPrompt: String) -> [[String: String]] {

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Add full conversation history (up to limit for comprehensive context)
        let recentHistory = conversationHistory.suffix(conversationHistoryLimit)
        for exchange in recentHistory {
            messages.append(["role": exchange.role, "content": exchange.content])
        }

        // Add the specific request
        messages.append(["role": "user", "content": userPrompt])

        return messages
    }

    private func callGroq(messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        log("Sending request to Groq...", category: .network, component: "AssistantClient")

        // Use retry logic for resilience
        let data = try await NetworkManager.shared.performRequestWithRetry(request)

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "AssistantClient", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        log("Generated \(content.count) chars", category: .assistant, component: "AssistantClient")
        return content
    }
}
