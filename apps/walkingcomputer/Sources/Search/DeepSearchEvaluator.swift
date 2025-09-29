import Foundation

// MARK: - Evaluation Models

struct EvaluationResult: Codable {
    let confidence: Double  // Overall confidence 0.0-1.0
    let coverage_by_subq: [String: Double]?  // Per-subquestion confidence
    let verdict: String  // "answer", "explore", or "insufficient"
    let answer: String?  // Provided when verdict is "answer"
    let next_queries: [NextQuery]?  // Only if verdict is "explore"

    // Legacy fields for compatibility (will be removed later)
    var coverage: Double { confidence }
    var max_domain_share: Double { 0.3 }  // Default value
    var freshness_ok: Bool { true }
}

struct NextQuery: Codable {
    let subq_id: String  // Which subquestion this targets
    let query: String  // The actual search query
    let priority: Double  // Priority 0.0-1.0
}

// Legacy structure for backward compatibility
struct SearchRefinement: Codable {
    let q: String
    let queries: [String]
    let add_domains: [String]?
}

// MARK: - Deep Search Evaluator

class DeepSearchEvaluator {
    private let groqApiKey: String
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"
    private let modelId: String  // Will be configured from environment

    private let systemPrompt = """
    You are a research evaluator using Kimi K2's structured reasoning capabilities.

    Task: Evaluate search evidence and decide next action.

    For each subquestion, assess:
    1. Evidence quality (0.0 = no evidence, 1.0 = comprehensive evidence)
    2. Information gaps that could improve the answer

    Decision logic:
    - confidence > 0.6 → verdict: "answer" (we have enough)
    - confidence 0.3-0.6 → verdict: "explore" (refine specific gaps)
    - confidence < 0.3 → verdict: "insufficient" (evidence very limited)

    Output JSON structure:
    {
        "confidence": <0.0-1.0 overall confidence>,
        "coverage_by_subq": {
            "subq_1": <0.0-1.0>,
            "subq_2": <0.0-1.0>
        },
        "verdict": "answer" | "explore" | "insufficient",
        "answer": "<ALWAYS provide best answer from available evidence, even if limited. For 'insufficient' verdict, prefix with 'Based on limited findings:'>",
        "next_queries": [
            {
                "subq_id": "subq_2",
                "query": "specific search string",
                "priority": <0.0-1.0>
            }
        ]
    }

    Important:
    - Be permissive: partial answers are valuable
    - ALWAYS provide an answer in the "answer" field, even for "insufficient" verdict
    - Generate specific, literal search queries (not questions)
    - Cite sources naturally: "According to X..."
    - Focus on gaps, don't repeat successful searches
    - Maximum 5 next_queries, prioritize by importance
    - Never say "I don't know" or "insufficient information" - always synthesize the best answer from available evidence
    """

    init(groqApiKey: String, modelId: String? = nil) {
        self.groqApiKey = groqApiKey
        // Use Kimi K2 for better structured output and reasoning
        self.modelId = modelId ?? "moonshotai/kimi-k2-instruct-0905"
    }

    func evaluateEvidence(plan: SearchPlan, evidence: [SearchEvidence]) async throws -> EvaluationResult {
        log("[EVALUATOR] Starting evaluation of evidence", category: .search)

        // Calculate basic metrics
        let coverage = calculateCoverage(evidence: evidence)
        let maxDomainShare = calculateMaxDomainShare(evidence: evidence)
        let freshnessOk = checkFreshness(plan: plan, evidence: evidence)

        log("[EVALUATOR] Coverage: \(String(format: "%.2f", coverage))", category: .search)
        log("[EVALUATOR] Max domain share: \(String(format: "%.2f", maxDomainShare))", category: .search)
        log("[EVALUATOR] Freshness: \(freshnessOk ? "OK" : "outdated")", category: .search)

        // Build prompt for LLM evaluation
        let prompt = buildEvaluationPrompt(plan: plan, evidence: evidence, coverage: coverage, maxDomainShare: maxDomainShare, freshnessOk: freshnessOk)

        // Get evaluation from LLM
        let evaluation = try await callLLM(prompt: prompt)

        // Log the verdict
        log("[EVALUATOR] Verdict: \(evaluation.verdict)", category: .search)
        if let answer = evaluation.answer {
            log("[EVALUATOR] Answer length: \(answer.count) chars", category: .search)
            let preview = String(answer.prefix(100))
            log("[EVALUATOR] Answer preview: \"\(preview)...\"", category: .search)
        }
        if let nextQueries = evaluation.next_queries, !nextQueries.isEmpty {
            log("[EVALUATOR] Proposed \(nextQueries.count) next queries", category: .search)
            for query in nextQueries {
                log("[EVALUATOR] Next: \(query.subq_id) - \(query.query) (priority: \(query.priority))", category: .search)
            }
        }

        return evaluation
    }

    // MARK: - Metric Calculations

    private func calculateCoverage(evidence: [SearchEvidence]) -> Double {
        let totalSubqs = evidence.count
        guard totalSubqs > 0 else { return 0.0 }

        let subqsWithFacts = evidence.filter { !$0.snippets.isEmpty }.count
        return Double(subqsWithFacts) / Double(totalSubqs)
    }

    private func calculateMaxDomainShare(evidence: [SearchEvidence]) -> Double {
        var domainCounts: [String: Int] = [:]
        var totalSnippets = 0

        for item in evidence {
            for snippet in item.snippets {
                domainCounts[snippet.source, default: 0] += 1
                totalSnippets += 1
            }
        }

        guard totalSnippets > 0 else { return 0.0 }

        let maxCount = domainCounts.values.max() ?? 0
        return Double(maxCount) / Double(totalSnippets)
    }

    private func checkFreshness(plan: SearchPlan, evidence: [SearchEvidence]) -> Bool {
        // For now, assume freshness is OK if we have any evidence
        // In a real implementation, would check publish dates against requirements
        return true
    }

    // MARK: - LLM Integration

    private func buildEvaluationPrompt(plan: SearchPlan, evidence: [SearchEvidence], coverage: Double, maxDomainShare: Double, freshnessOk: Bool) -> String {
        var sections: [String] = []

        // Goal and subquestions
        sections.append("Goal: \(plan.goal)")
        sections.append("Subquestions:")
        for (index, subq) in plan.subqs.enumerated() {
            sections.append("\(index + 1). \(subq.q)")
        }

        // Evidence
        sections.append("\nEvidence collected:")
        for (index, item) in evidence.enumerated() {
            sections.append("\nSubq \(index + 1): \(item.subquestion)")
            if item.snippets.isEmpty {
                sections.append("  No evidence found")
            } else {
                sections.append("  \(item.snippets.count) snippets:")
                for snippet in item.snippets.prefix(3) {  // Show first 3 snippets
                    let preview = String(snippet.text.prefix(150))
                    sections.append("  - [\(snippet.source)] \"\(preview)...\"")
                }
            }
        }

        // Metrics
        sections.append("\nMetrics calculated:")
        sections.append("- Coverage: \(String(format: "%.2f", coverage)) (subqs with facts / total)")
        sections.append("- Max domain share: \(String(format: "%.2f", maxDomainShare))")
        sections.append("- Freshness: \(freshnessOk ? "OK" : "needs update")")

        // Instructions
        sections.append("\nBased on the evidence, determine if we have enough information to answer the goal.")
        sections.append("If yes (coverage ≥ 0.7 and good diversity), write a concise answer.")
        sections.append("If no, propose specific new queries to fill gaps.")

        return sections.joined(separator: "\n")
    }

    private func callLLM(prompt: String) async throws -> EvaluationResult {
        log("[EVALUATOR] Sending evaluation request to LLM", category: .search)

        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(groqApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,  // Lower temperature for consistent evaluation
            "max_tokens": 1200,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let startTime = Date()
        let data = try await NetworkManager.shared.performRequestWithRetry(request)
        let evalTime = Date().timeIntervalSince(startTime)

        log("[EVALUATOR] Response received in \(String(format: "%.2f", evalTime))s", category: .search)

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "DeepSearchEvaluator", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response format from LLM"])
        }

        log("[EVALUATOR] Raw response: \(content)", category: .search)

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8) else {
            throw NSError(domain: "DeepSearchEvaluator", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to convert response to data"])
        }

        do {
            let evaluation = try JSONDecoder().decode(EvaluationResult.self, from: contentData)
            return evaluation
        } catch {
            log("[EVALUATOR] Failed to parse evaluation JSON: \(error)", category: .search)

            // Return a default "answer" verdict with basic answer if parsing fails
            return EvaluationResult(
                confidence: 0.5,
                coverage_by_subq: nil,
                verdict: "answer",
                answer: "I found some information but had difficulty processing it. Please try rephrasing your question.",
                next_queries: nil
            )
        }
    }
}