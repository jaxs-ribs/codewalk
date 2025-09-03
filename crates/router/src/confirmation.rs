use crate::types::{RouterAction, RouterResponse};

/// Analyzes a confirmation response and determines the user's intent
pub fn analyze_confirmation_response(text: &str) -> RouterAction {
    let lower = text.to_lowercase();
    let words: Vec<&str> = lower.split_whitespace().collect();
    
    // Check for continue/resume patterns
    if contains_any(&lower, &["continue", "resume", "pick up", "where we left", "previous", "last session"]) {
        return RouterAction::ContinuePrevious;
    }
    
    // Check for new/fresh session patterns
    if contains_any(&lower, &["new", "fresh", "start over", "from scratch", "clean", "restart"]) {
        return RouterAction::StartNew;
    }
    
    // Check for decline patterns
    if is_negative_response(&words, &lower) {
        return RouterAction::DeclineSession;
    }
    
    // Check for ambiguous affirmatives (just "yes", "okay", "sure" without context)
    if is_ambiguous_affirmative(&words, &lower) {
        return RouterAction::AmbiguousConfirmation;
    }
    
    // Everything else is unintelligible
    RouterAction::UnintelligibleResponse
}

/// Check if text contains any of the patterns
fn contains_any(text: &str, patterns: &[&str]) -> bool {
    patterns.iter().any(|p| text.contains(p))
}

/// Check for negative responses
fn is_negative_response(words: &[&str], text: &str) -> bool {
    // Direct negatives
    if words.contains(&"no") || words.contains(&"nope") || words.contains(&"nah") {
        return true;
    }
    
    // Phrases indicating decline
    contains_any(text, &["not now", "cancel", "never mind", "forget it", "don't", "stop"])
}

/// Check for ambiguous affirmatives that need clarification
fn is_ambiguous_affirmative(words: &[&str], text: &str) -> bool {
    // Single word affirmatives without context
    if words.len() == 1 {
        return matches!(words[0], "yes" | "yeah" | "yep" | "okay" | "ok" | "sure" | "alright");
    }
    
    // Short phrases that are still ambiguous
    if words.len() <= 2 && words.contains(&"yes") && !contains_any(text, &["continue", "new", "fresh", "previous"]) {
        return true;
    }
    
    // "yes please" or "okay please" without specifying what
    if text == "yes please" || text == "okay please" || text == "sure thing" {
        return true;
    }
    
    false
}

/// Creates a RouterResponse for a confirmation analysis
pub fn create_confirmation_response(action: RouterAction) -> RouterResponse {
    let (reason, confidence) = match &action {
        RouterAction::ContinuePrevious => ("User wants to continue previous session", 0.9),
        RouterAction::StartNew => ("User wants to start a new session", 0.9),
        RouterAction::DeclineSession => ("User declined to start a session", 0.95),
        RouterAction::AmbiguousConfirmation => ("User said yes but didn't specify continue or new", 0.8),
        RouterAction::UnintelligibleResponse => ("Could not understand the response", 0.7),
        _ => ("Invalid confirmation action", 0.0),
    };
    
    RouterResponse {
        action,
        prompt: None,
        reason: Some(reason.to_string()),
        confidence,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_continue_patterns() {
        assert_eq!(analyze_confirmation_response("yes continue"), RouterAction::ContinuePrevious);
        assert_eq!(analyze_confirmation_response("continue where we left off"), RouterAction::ContinuePrevious);
        assert_eq!(analyze_confirmation_response("resume please"), RouterAction::ContinuePrevious);
        assert_eq!(analyze_confirmation_response("pick up from before"), RouterAction::ContinuePrevious);
        assert_eq!(analyze_confirmation_response("use the previous session"), RouterAction::ContinuePrevious);
    }
    
    #[test]
    fn test_new_patterns() {
        assert_eq!(analyze_confirmation_response("start new"), RouterAction::StartNew);
        assert_eq!(analyze_confirmation_response("fresh session please"), RouterAction::StartNew);
        assert_eq!(analyze_confirmation_response("start over"), RouterAction::StartNew);
        assert_eq!(analyze_confirmation_response("from scratch"), RouterAction::StartNew);
        assert_eq!(analyze_confirmation_response("new one"), RouterAction::StartNew);
    }
    
    #[test]
    fn test_decline_patterns() {
        assert_eq!(analyze_confirmation_response("no"), RouterAction::DeclineSession);
        assert_eq!(analyze_confirmation_response("no thanks"), RouterAction::DeclineSession);
        assert_eq!(analyze_confirmation_response("not now"), RouterAction::DeclineSession);
        assert_eq!(analyze_confirmation_response("cancel"), RouterAction::DeclineSession);
        assert_eq!(analyze_confirmation_response("nope"), RouterAction::DeclineSession);
    }
    
    #[test]
    fn test_ambiguous_patterns() {
        assert_eq!(analyze_confirmation_response("yes"), RouterAction::AmbiguousConfirmation);
        assert_eq!(analyze_confirmation_response("okay"), RouterAction::AmbiguousConfirmation);
        assert_eq!(analyze_confirmation_response("sure"), RouterAction::AmbiguousConfirmation);
        assert_eq!(analyze_confirmation_response("yes please"), RouterAction::AmbiguousConfirmation);
        assert_eq!(analyze_confirmation_response("yeah"), RouterAction::AmbiguousConfirmation);
    }
    
    #[test]
    fn test_unintelligible_patterns() {
        assert_eq!(analyze_confirmation_response("purple banana"), RouterAction::UnintelligibleResponse);
        assert_eq!(analyze_confirmation_response("what?"), RouterAction::UnintelligibleResponse);
        assert_eq!(analyze_confirmation_response("asdfgh"), RouterAction::UnintelligibleResponse);
        assert_eq!(analyze_confirmation_response("maybe later"), RouterAction::UnintelligibleResponse);
    }
}